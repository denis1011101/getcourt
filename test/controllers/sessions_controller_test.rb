require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "should get new" do
    get new_session_url
    assert_response :success
  end

  test "sign-in page tells bot users how to link their existing account" do
    get new_session_url

    assert_response :success
    assert_select '[data-testid="telegram-signup-hint"]', 1
    assert_select '[data-testid="telegram-signup-hint"] summary', text: "Did you previously sign up through Telegram?"
    assert_select '[data-testid="telegram-signup-hint"] a[href=?]', notifications_account_path
  end

  test "should create session" do
    post session_url, params: { email: "sessions_test@example.com" }
    assert_redirected_to root_path
  end

  test "new user created from en locale stores en telegram locale" do
    host! "en.getcourt.co"
    email = "sessions_en_locale@example.com"

    post session_url, params: { email: email }

    assert_redirected_to root_path
    user = User.find_by!(email: email)
    assert_equal "en", user.telegram_locale
    assert_equal "en", user.locale
    assert_equal "email", user.notification_channel
  ensure
    User.find_by(email: email)&.destroy if defined?(email)
  end

  test "new user created from es locale stores es telegram locale" do
    host! "es.getcourt.co"
    email = "sessions_es_locale@example.com"

    post session_url, params: { email: email }

    assert_redirected_to root_path
    user = User.find_by!(email: email)
    assert_equal "es", user.telegram_locale
    assert_equal "es", user.locale
  ensure
    User.find_by(email: email)&.destroy if defined?(email)
  end

  test "sign in does not overwrite an existing web locale" do
    user = User.create!(email: "sessions_saved_locale@example.com", locale: "ru")

    post session_url, params: { email: user.email }

    assert_redirected_to root_path
    assert_equal "ru", user.reload.locale
  ensure
    user&.destroy
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

  test "verify page shows email copy for email verification" do
    user = User.create!(
      email: "sessions_verify_email@example.com",
      preferred_login_via: "email"
    )

    get verify_session_url, params: { email: user.email }

    assert_response :success
    assert_includes response.body, I18n.t("sessions.verify.title_email")
    assert_includes response.body, I18n.t("sessions.verify.subtitle_email")
  ensure
    user&.destroy
  end

  test "verify page shows telegram copy for telegram verification" do
    user = User.create!(
      email: "sessions_verify_telegram@example.com",
      preferred_login_via: "telegram"
    )

    get verify_session_url, params: { email: user.email }

    assert_response :success
    assert_includes response.body, I18n.t("sessions.verify.title_telegram")
    assert_includes response.body, I18n.t("sessions.verify.subtitle_telegram")
  ensure
    user&.destroy
  end

  # Проверка входа по коду: раньше почтовый метод пускал с любыми цифрами.
  { "email" => "email", "telegram" => "telegram" }.each do |method, via|
    test "a wrong code does not sign in a #{method} account with verification on" do
      user = user_with_code(via)

      post "/sign_in/verify", params: { email: user.email, code: "0000" }

      assert_response :unprocessable_entity
      assert_nil session[:user_id]
    end

    test "the right code signs in a #{method} account and cannot be reused" do
      user = user_with_code(via)
      code = user.login_code

      post "/sign_in/verify", params: { email: user.email, code: code }

      assert_redirected_to root_path
      assert_equal user.id, session[:user_id]
      assert_nil user.reload.login_code

      delete destroy_session_url
      post "/sign_in/verify", params: { email: user.email, code: code }

      assert_response :unprocessable_entity
      assert_nil session[:user_id]
    end
  end

  test "an empty code does not sign in" do
    user = user_with_code("email")

    post "/sign_in/verify", params: { email: user.email, code: "" }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "a code older than its lifetime does not sign in" do
    user = user_with_code("email")
    user.update_columns(login_code_sent_at: 16.minutes.ago)

    post "/sign_in/verify", params: { email: user.email, code: user.login_code }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "an account without verification still signs in without a code" do
    user = User.create!(email: "sessions_no_verification@example.com")

    post "/sign_in/verify", params: { email: user.email, code: "" }

    assert_redirected_to root_path
    assert_equal user.id, session[:user_id]
  end

  test "should destroy session" do
    delete destroy_session_url
    assert_redirected_to new_session_path
  end

  private

  def user_with_code(via)
    user = User.create!(
      email: "sessions_code_#{via}@example.com",
      require_verification: true,
      preferred_login_via: via,
      telegram_chat_id: via == "telegram" ? 123_456_789 : nil
    )
    user.generate_login_code!(via: via)
    user.reload
  end
end
