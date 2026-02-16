require "test_helper"

class Dashboard::StudentsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get dashboard_students_index_url
    assert_response :success
  end

  test "should get show" do
    get dashboard_students_show_url
    assert_response :success
  end
end
