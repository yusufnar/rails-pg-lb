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

    # Execute query on the reading role (replica)
    result = ApplicationRecord.connected_to(role: :reading) do
      ApplicationRecord.connection.select_one(sql)
    end

    if result
      @content = result["content"]
      @created_at = result["created_at"]
      @db_time = result["db_time"]
      @server_ip = result["server_ip"]
    end
    @app_ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }&.ip_address
  end
end
