require "test_helper"

class AccountVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "verify-me@example.com")
    @verified = User.create!(email: "already-verified@example.com", email_verified_at: Time.current)
  end

  teardown do
    @user&.destroy
    @verified&.destroy
  end

  test "guest must sign in first" do
    get new_account_verification_url

    assert_redirected_to new_session_path
  end

  test "already verified person is sent back to account security" do
    sign_in_as(@verified)

    get new_account_verification_url

    assert_redirected_to security_account_path
  end

  test "sending a code mails it to the account address" do
    sign_in_as(@user)

    assert_enqueued_emails 1 do
      post account_verification_url
    end

    assert_redirected_to new_account_verification_path
    assert_not_nil @user.reload.login_code
  end

  test "correct code confirms the account and returns to the remembered page" do
    sign_in_as(@user)
    get new_account_verification_url, headers: { "HTTP_REFERER" => court_url(courts(:feed_approved)) }
    code = @user.generate_login_code!(via: "email")

    patch account_verification_url, params: { code: code }

    assert_redirected_to court_path(courts(:feed_approved))
    assert_predicate @user.reload, :verified?
    assert_nil @user.login_code
  end

  test "wrong code leaves the account unconfirmed" do
    sign_in_as(@user)
    @user.generate_login_code!(via: "email")

    patch account_verification_url, params: { code: "0000-wrong" }

    assert_response :unprocessable_entity
    assert_not_predicate @user.reload, :verified?
  end

  private

  def sign_in_as(user)
    post session_url, params: { email: user.email }
  end
end
