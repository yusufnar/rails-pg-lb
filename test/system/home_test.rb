require "application_system_test_case"

class HomeTest < ApplicationSystemTestCase
  test "visiting the home page shows the heading and health monitor" do
    visit root_url

    assert_selector "h1", text: "Last Ynar Record"
    assert_selector "h3", text: "Database Health Monitor (via Redis)"
    assert_selector "table"
  end
end
