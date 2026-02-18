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
                  (pg_last_wal_receive_lsn() IS NULL OR pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()) as is_sync,
                  COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0) as lag_s
          )
          SELECT 
              receive_lsn,
              is_sync,
              ROUND(lag_s::numeric, 2) as lag_s,
              CASE WHEN is_sync THEN 0 ELSE ROUND(lag_s::numeric, 2) END as real_lag_s
          FROM stats;
        SQL
        
        result = conn.exec(query).collect { |row| row }[0]
        lag_s = result['lag_s'].to_f
        real_lag_s = result['real_lag_s'].to_f
        is_sync = result['is_sync'] == 't'
        receive_lsn = result['receive_lsn']
        
        healthy = !is_paused && (real_lag_s <= MAX_LAG_SECONDS)
        
        message = []
        message << "Replay paused" if is_paused
        message << "In sync" if is_sync && !is_paused
        message << "Syncing..." if !is_sync && !is_paused
        message << "Raw Lag: #{lag_s}s"
        message << "Real Lag: #{real_lag_s}s"
        message << "Receive LSN: #{receive_lsn || 'NULL'}"
        
        status = { 
          role: 'replica', 
          healthy: healthy, 
          lag_ms: (real_lag_s * 1000).to_i,
          message: message.join(", "),
          is_sync: is_sync,
          is_paused: is_paused
        }
      end
    end
    
    conn.close
    status
  rescue => e
    { role: 'unknown', healthy: false, message: e.message }
  end
end

puts "Starting DB Health Check monitor..."
loop do
  NODES.each do |role_name, host|
    status = check_node(host, role_name == :primary ? :primary : :replica)
    new_status_json = status.to_json
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
    msg += " (Lag: #{status[:lag_ms] || 'N/A'}ms)"
    msg += " Details: #{status[:message]}" if status[:message]
    puts msg
  end
  
  sleep CHECK_INTERVAL
end
