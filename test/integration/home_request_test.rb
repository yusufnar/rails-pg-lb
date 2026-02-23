require "test_helper"

class HomeRequestTest < ActionDispatch::IntegrationTest
  test "visiting the home page returns JSON with correct structure" do
    get root_url
    assert_response :success
    
    json_response = JSON.parse(response.body)
    
    assert_includes json_response.keys, "last_record"
    assert_includes json_response.keys, "connection_info"
    assert_includes json_response.keys, "db_statuses"
    
    assert_includes json_response["connection_info"].keys, "connected_host"
    assert_includes json_response["connection_info"].keys, "server_ip"
  end

  test "api status endpoint returns JSON" do
    get api_status_url
    assert_response :success
    assert_equal "application/json; charset=utf-8", response.content_type
  end
end
