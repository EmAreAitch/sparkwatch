require "test_helper"

class Dashboard::CohortsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get dashboard_cohorts_index_url
    assert_response :success
  end

  test "should get show" do
    get dashboard_cohorts_show_url
    assert_response :success
  end
end
