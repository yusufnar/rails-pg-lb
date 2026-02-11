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
        connect_timeout: 0.1,
        read_timeout: 0.1
      )
      @db_statuses = {}
      [:primary, :replica_1, :replica_2].each do |role|
        status_json = redis.get("db_status:#{role}")
        @db_statuses[role] = status_json ? JSON.parse(status_json) : { "healthy" => false, "message" => "No data" }
      end
    rescue StandardError => e
      Rails.logger.error "HomeController: Redis error (#{e.class}: #{e.message})"
      @db_statuses = [:primary, :replica_1, :replica_2].each_with_object({}) do |role, hash|
        hash[role] = { "healthy" => false, "message" => "Redis Unavailable" }
      end
    end
  end
end
