require 'pg'
require 'redis'
require 'json'

# Configuration from environment
CHECK_INTERVAL = 5
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

$redis = Redis.new(url: REDIS_URL)

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
                  pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() as is_sync,
                  COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0) as lag_s
          )
          SELECT 
              is_sync,
              ROUND(lag_s::numeric, 2) as lag_s,
              CASE WHEN is_sync THEN 0 ELSE ROUND(lag_s::numeric, 2) END as real_lag_s
          FROM stats;
        SQL
        
        result = conn.exec(query).collect { |row| row }[0]
        lag = result['real_lag_s'].to_f
        is_sync = result['is_sync'] == 't'
        
        healthy = !is_paused && (lag <= MAX_LAG_SECONDS)
        
        message = []
        message << "Replay paused" if is_paused
        message << "In sync" if is_sync && !is_paused
        message << "Syncing..." if !is_sync && !is_paused
        
        status = { 
          role: 'replica', 
          healthy: healthy, 
          lag_ms: (lag * 1000).to_i,
          message: message.join(", ")
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
    $redis.set("db_status:#{role_name}", status.to_json)
    # Debug output
    puts "[#{Time.now}] #{role_name} (#{host}): #{status[:healthy] ? 'HEALTHY' : 'UNHEALTHY'} (Lag: #{status[:lag_ms] || 'N/A'}ms)"
  end
  
  sleep CHECK_INTERVAL
end
