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
        lag = conn.exec(
          "SELECT CASE
             WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
             WHEN pg_last_xact_replay_timestamp() IS NULL THEN 0
             ELSE extract(epoch from (now() - pg_last_xact_replay_timestamp()))
           END"
        ).getvalue(0, 0).to_f
        
        healthy = lag <= MAX_LAG_SECONDS
        status = { role: 'replica', healthy: healthy, lag_ms: (lag * 1000).to_i }
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
