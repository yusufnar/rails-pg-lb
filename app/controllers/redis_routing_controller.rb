class RedisRoutingController < ApplicationController
  def show
    routing_time_ms = Thread.current[:redis_routing_duration]
    routing_time_ms = routing_time_ms ? (routing_time_ms * 1000).round(3) : nil

    cache_ttl = DatabaseLoadBalancer::CACHE_TTL
    lb = DatabaseLoadBalancer.instance

    # Determine source: cache hit vs Redis fetch
    source = routing_time_ms == 0 ? "cache" : "redis"

    render json: {
      timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S.%L"),
      redis_routing_time_ms: routing_time_ms,
      source: source,
      cache_ttl_seconds: cache_ttl,
      current_role: ActiveRecord::Base.current_role.to_s,
      connected_host: ApplicationRecord.connection_pool.db_config.host
    }
  end
end
