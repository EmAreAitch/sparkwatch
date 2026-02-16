require "test_helper"

class Dashboard::OverviewControllerTest < ActionDispatch::IntegrationTest
  test "should get platform" do
    get dashboard_overview_platform_url
    assert_response :success
  end

  test "should get student" do
    get dashboard_overview_student_url
    assert_response :success
  end

  test "should get cohort" do
    get dashboard_overview_cohort_url
    assert_response :success
  end
end
