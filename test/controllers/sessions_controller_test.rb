require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "should get new" do
    get new_session_url
    assert_response :success
  end

  test "should create session" do
    post session_url, params: { email: "sessions_test@example.com" }
    assert_redirected_to root_path
  end

  test "should send email login code when email verification is required" do
    user = User.create!(
      email: "sessions_email_code@example.com",
      require_verification: true,
      preferred_login_via: "email"
    )

    assert_enqueued_emails 1 do
      post session_url, params: { email: user.email }
    end

    assert_redirected_to verify_session_path(email: user.email)
    user.reload
    assert_equal "email", user.login_via
    assert user.login_code.present?
  end

  test "should destroy session" do
    delete destroy_session_url
    assert_redirected_to new_session_path
  end
end
