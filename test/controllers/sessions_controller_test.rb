require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_session_url
    assert_response :success
  end

  test "should create session" do
    post session_url, params: { email: "sessions_test@example.com" }
    assert_redirected_to root_path
  end

  test "should destroy session" do
    delete destroy_session_url
    assert_redirected_to new_session_path
  end
end
