require 'pg'
require 'redis'
require 'json'

$stdout.sync = true

# Configuration from environment
CHECK_INTERVAL = 1
MAX_LAG_SECONDS = 1.0
REDIS_URL = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')

NODES = {
  primary: ENV.fetch('PRIMARY_DB_HOST', 'postgres-primary'),
  replica_1: ENV.fetch('REPLICA1_DB_HOST', 'postgres-replica1'),
  replica_2: ENV.fetch('REPLICA2_DB_HOST', 'postgres-replica2')
}

DB_CONFIG = {
  user: 'postgres',
  password: 'password',
  dbname: 'app_development'
}

$redis = nil

def redis_client
  $redis ||= Redis.new(url: REDIS_URL)
rescue => e
  puts "[#{Time.now}] WARN: Redis connection failed: #{e.message}"
  nil
end

def check_node(host, role_expected)
  begin
    conn = PG.connect(DB_CONFIG.merge(host: host, connect_timeout: 2))
    
    # Check if replica
    is_recovery = conn.exec("SELECT pg_is_in_recovery()").getvalue(0, 0) == 't'
    
    if role_expected == :primary
      if is_recovery
        status = { role: 'replica', healthy: false, message: 'Expected primary but found replica' }
      else
        status = { role: 'primary', healthy: true, lag_ms: 0 }
      end
    else
      if !is_recovery
        status = { role: 'primary', healthy: false, message: 'Expected replica but found primary' }
      else
        # 1. Check if WAL replay is explicitly paused
        is_paused = conn.exec("SELECT pg_is_wal_replay_paused()").getvalue(0, 0) == 't'
        
        # 2. Execute user-provided lag check SQL
        query = <<~SQL
          WITH stats AS (
              SELECT 
                  pg_last_wal_receive_lsn() as receive_lsn,
                  (pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()) as is_sync,
                  COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0) as lag_s
          ),
          wal_recv AS (
              SELECT
                  status as replication_status,
                  EXTRACT(EPOCH FROM (now() - last_msg_send_time)) as last_msg_send_lag_s,                  
                  EXTRACT(EPOCH FROM (now() - last_msg_receipt_time)) as last_msg_receipt_lag_s,
                  EXTRACT(EPOCH FROM (last_msg_receipt_time - last_msg_send_time)) as transport_lag_s,
                  EXTRACT(EPOCH FROM (now() - latest_end_time)) as last_wal_end_lag_s
              FROM pg_stat_wal_receiver
          )
          SELECT 
              receive_lsn,
              is_sync,
              replication_status,
              ROUND(lag_s::numeric, 3) as lag_s,
              CASE WHEN is_sync THEN 0 ELSE ROUND(lag_s::numeric, 3) END as real_lag_s,
              ROUND(last_msg_receipt_lag_s::numeric, 3) as last_msg_receipt_lag_s,
              ROUND(last_msg_send_lag_s::numeric, 3) as last_msg_send_lag_s,
              ROUND(transport_lag_s::numeric, 3) as transport_lag_s,
              ROUND(last_wal_end_lag_s::numeric, 3) as last_wal_end_lag_s
          FROM stats
          LEFT JOIN wal_recv ON true;
        SQL
        
        result = conn.exec(query).collect { |row| row }[0]
        lag_s = result['lag_s'].to_f
        real_lag_s = result['real_lag_s'].to_f
        is_sync = result['is_sync'] == 't'
        last_msg_receipt_lag_s = result['last_msg_receipt_lag_s'] ? result['last_msg_receipt_lag_s'].to_f : nil
        last_wal_end_lag_s = result['last_wal_end_lag_s']
        transport_lag_s = result['transport_lag_s']
        last_msg_send_lag_s = result['last_msg_send_lag_s']
        receive_lsn = result['receive_lsn']
        replication_status = result['replication_status']
        
        is_zombie = replication_status == 'streaming' && last_msg_receipt_lag_s && last_msg_receipt_lag_s > 20
        healthy = !is_paused && !is_zombie && (real_lag_s <= MAX_LAG_SECONDS)
        
        message = []
        message << "Replay paused" if is_paused
        message << "Zombie connection detected" if is_zombie
        message << "In sync" if is_sync && !is_paused
        message << "Syncing..." if !is_sync && !is_paused
        message << "Status: #{replication_status}" if replication_status
        message << "Raw Lag: #{lag_s}s"
        message << "Real Lag: #{real_lag_s}s"
        message << "Msg Lag: #{last_msg_receipt_lag_s}s" if last_msg_receipt_lag_s
        message << "WAL End Lag: #{last_wal_end_lag_s}s" if last_wal_end_lag_s
        message << "Transport Lag: #{transport_lag_s}s" if transport_lag_s
        message << "Msg Send Lag: #{last_msg_send_lag_s}s" if last_msg_send_lag_s
        message << "Receive LSN: #{receive_lsn || 'NULL'}"
        
        status = { 
          role: 'replica', 
          healthy: healthy, 
          lag_ms: (real_lag_s * 1000).to_i,
          message: message.join(", "),
          is_sync: is_sync,
          is_paused: is_paused,
          replication_status: replication_status,
          last_msg_receipt_lag_s: last_msg_receipt_lag_s
        }
      end
    end
    
    conn.close
    status.merge(role_expected: role_expected, is_recovery: is_recovery)
  rescue => e
    { role: 'unknown', healthy: false, message: e.message, role_expected: role_expected, is_recovery: nil }
  end
end

puts "Starting DB Health Check monitor..."
loop do
  NODES.each do |role_name, host|
    status = check_node(host, role_name == :primary ? :primary : :replica)
    # Prune JSON for Redis to save space; keep only used fields
    pruned_status = {
      healthy: status[:healthy],
      lag_ms: status[:lag_ms] || 0,
      last_msg_receipt_lag_s: status[:last_msg_receipt_lag_s]
    }
    new_status_json = pruned_status.to_json
    key = "db_status:#{role_name}"

    begin
      r = redis_client
      if r
        current_status_json = r.get(key)
        if new_status_json != current_status_json
          r.set(key, new_status_json)
        end
      else
        puts "[#{Time.now}] WARN: Redis unavailable, skipping status update for #{role_name}"
      end
    rescue Redis::CannotConnectError, RedisClient::CannotConnectError, SocketError => e
      puts "[#{Time.now}] WARN: Redis error for #{role_name}: #{e.message}"
      $redis = nil  # Reset so it reconnects next cycle
    rescue => e
      puts "[#{Time.now}] WARN: Unexpected Redis error for #{role_name}: #{e.message}"
      $redis = nil
    end
    # Debug output
    msg = "[#{Time.now}] #{role_name} (#{host}): #{status[:healthy] ? 'HEALTHY' : 'UNHEALTHY'}"
    msg += " (Expected: #{status[:role_expected]}, Recovery: #{status[:is_recovery]})"
    msg += " (Lag: #{status[:lag_ms] || 'N/A'}ms)"
    msg += " Details: #{status[:message]}" if status[:message]
    puts msg
  end
  
  sleep CHECK_INTERVAL
end
