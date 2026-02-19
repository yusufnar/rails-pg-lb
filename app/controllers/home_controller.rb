class HomeController < ApplicationController
  def index
    # Rails automatically uses the reading role for GET requests/actions
    sql = <<~SQL
      SELECT
        content,
        created_at,
        to_char(NOW(), 'YYYY-MM-DD HH24:MI:SS.MS') as db_time,
        inet_server_addr() as server_ip
      FROM ynars
      ORDER BY id DESC
      LIMIT 1
    SQL

    # Query executed within the connection context set by ApplicationController
    result = ApplicationRecord.connection.select_one(sql)

    if result
      @content = result["content"]
      @created_at = result["created_at"]
      @db_time = result["db_time"]
      @server_ip = result["server_ip"]
    end
    @app_ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }&.ip_address

    # Fetch Redis statuses
    begin
      redis = Redis.new(
        url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
        connect_timeout: 0.5,
        read_timeout: 0.5
      )
      @db_statuses = {}
      [ :primary, :replica_1, :replica_2 ].each do |role|
        status_json = redis.get("db_status:#{role}")
        @db_statuses[role] = status_json ? JSON.parse(status_json) : { "healthy" => false, "message" => "No data" }
      end
    rescue StandardError => e
      Rails.logger.error "HomeController: Redis error (#{e.class}: #{e.message})"
      @db_statuses = [ :primary, :replica_1, :replica_2 ].each_with_object({}) do |role, hash|
        hash[role] = { "healthy" => false, "message" => "Redis Unavailable" }
      end
    end

    respond_to do |format|
      format.html
      format.json do
        render json: {
          last_record: {
            content: @content,
            created_at: @created_at
          },
          connection_info: {
            connected_host: ApplicationRecord.connection_pool.db_config.host,
            server_ip: @server_ip,
            app_ip: @app_ip,
            current_role: ActiveRecord::Base.current_role,
            current_shard: ActiveRecord::Base.current_shard,
            prevent_writes: ActiveRecord::Base.connected_to?(role: :reading),
            db_time: @db_time,
            redis_routing_time_ms: Thread.current[:redis_routing_duration] ? (Thread.current[:redis_routing_duration] * 1000).round(3) : 0,
            source: Thread.current[:lb_source] || "unknown"
          },
          db_statuses: @db_statuses
        }
      end
    end
  end
end
