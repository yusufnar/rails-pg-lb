class DatabaseLoadBalancer
  include Singleton

  CACHE_TTL = 2.second

  def initialize
    @replica_roles = [ :replica_1, :replica_2 ]
    @mutex = Mutex.new
    @redis = Redis.new(
      url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
      connect_timeout: 0.1,
      read_timeout: 0.1
    )
    @redis_last_failure_at = nil
    @failure_backoff = 10.seconds
    @last_checked_at = nil
    @cached_healthy_roles = []
  end

  def reading_role
    # 1. Check Cache
    cached_roles = @mutex.synchronize do
      if @last_checked_at && (Time.current - @last_checked_at) < CACHE_TTL
        @cached_healthy_roles
      end
    end

    if cached_roles
      Thread.current[:redis_routing_duration] = 0
      return select_role(cached_roles, "cache hit")
    end

    # 2. Fetch from Redis (if not cached)
    healthy_roles = []
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Circuit Breaker: Skip Redis if we had a recent failure
    circuit_open = @mutex.synchronize do
      @redis_last_failure_at && (Time.current - @redis_last_failure_at) < @failure_backoff
    end

    if circuit_open
      healthy_roles = @replica_roles
      duration = 0
    else
      begin
        @replica_roles.each do |role|
          status_json = @redis.get("db_status:#{role}")
          if status_json
            status = JSON.parse(status_json)
            healthy_roles << role if status["healthy"]
          end
        end
      rescue StandardError => e
        @mutex.synchronize { @redis_last_failure_at = Time.current }
        Rails.logger.error "DatabaseLoadBalancer: Redis error (#{e.class}: #{e.message}). Circuit breaker opened for #{@failure_backoff}s. Falling back to all replicas."
        healthy_roles = @replica_roles
      end
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    end

    # 3. Update Cache
    @mutex.synchronize do
      @cached_healthy_roles = healthy_roles
      @last_checked_at = Time.current
    end

    Thread.current[:redis_routing_duration] = duration
    select_role(healthy_roles, "Redis fetch took #{(duration * 1000).round(2)}ms")
  end

  private

  def select_role(healthy_roles, source_info)
    role = if healthy_roles.any?
      @mutex.synchronize do
        @last_index ||= 0
        @last_index = (@last_index + 1) % healthy_roles.size
        healthy_roles[@last_index]
      end
    else
      :writing
    end

    Rails.logger.info "DatabaseLoadBalancer: Selected role #{role} from healthy list: #{healthy_roles} (#{source_info})"
    role
  end
end
