class DatabaseLoadBalancer
  include Singleton

  CHECK_INTERVAL = 5.seconds

  def initialize
    @replica_roles = [:replica_1, :replica_2]
    @mutex = Mutex.new
    @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  end

  def reading_role
    healthy_roles = []
    
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      @replica_roles.each do |role|
        status_json = @redis.get("db_status:#{role}")
        if status_json
          status = JSON.parse(status_json)
          healthy_roles << role if status["healthy"]
        end
      end
    rescue Redis::BaseConnectionError => e
      Rails.logger.error "DatabaseLoadBalancer: Redis is down (#{e.message}). Falling back to all replicas."
      healthy_roles = @replica_roles
    end
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    Thread.current[:redis_routing_duration] = duration
    
    role = if healthy_roles.any?
      # Simple round robin based on current time or random for simplicity since we don't track state across requests here easily without a mutex on a shared list
      # But we want to maintain the round-robin feel.
      # Let's use a simple global counter or just sample for now if we don't want to overcomplicate.
      # Actually, since we want to give the user what they had:
      @mutex.synchronize do
        @last_index ||= 0
        @last_index = (@last_index + 1) % healthy_roles.size
        healthy_roles[@last_index]
      end
    else
      :writing
    end
    
    Rails.logger.info "DatabaseLoadBalancer: Selected role #{role} from healthy list: #{healthy_roles} (Redis fetch took #{(duration * 1000).round(2)}ms)"
    role
  end
end
