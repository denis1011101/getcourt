require "test_helper"

class ApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "a guest is sent to sign in" do
    post api_token_url

    assert_redirected_to new_session_path
  end

  test "an unverified account cannot get a token" do
    sign_in_as("api-token-stranger@example.com")

    post api_token_url

    assert_redirected_to new_account_verification_path
    assert_empty ApiToken.all

    post api_token_url, as: :json

    assert_response :forbidden
  end

  test "a verified account issues, reads and revokes its token" do
    user = sign_in_as("api-token-holder@example.com")
    user.update!(email_verified_at: Time.current)
    confirm_ownership(user)

    post api_token_url, as: :json

    assert_response :created
    token = JSON.parse(response.body)
    assert_equal 64, token["token"].length
    assert token["expires_at"].present?

    get api_token_url, as: :json

    assert_response :success
    assert_equal token["token"], JSON.parse(response.body)["token"]

    delete api_token_url, as: :json

    assert_response :no_content
    assert_empty user.api_tokens.active
  end

  test "a linked telegram is enough, and the account page shows the token" do
    user = sign_in_as("api-token-telegram@example.com")
    user.update!(telegram_chat_id: 987_654_321)
    confirm_ownership(user)

    post api_token_url

    assert_redirected_to security_account_path

    get security_account_url

    assert_response :success
    assert_includes response.body, user.api_tokens.active.first.token
  end

  # Вход в аккаунт может не требовать кода, поэтому одной почты владельца мало:
  # иначе чужой читает и перевыпускает токен, просто представившись им.
  test "without confirmation in this session the token stays out of reach" do
    user = sign_in_as("api-token-unconfirmed@example.com")
    user.update!(email_verified_at: Time.current)
    existing = ApiToken.issue_for(user)

    get api_token_url, as: :json
    assert_response :forbidden
    assert_equal "confirmation_required", JSON.parse(response.body)["error"]

    post api_token_url, as: :json
    assert_response :forbidden

    delete api_token_url, as: :json
    assert_response :forbidden

    get security_account_url
    assert_response :success
    assert_not_includes response.body, existing.token
    assert_equal existing.token, user.api_tokens.active.first.token
  end

  test "a wrong code does not confirm ownership" do
    user = sign_in_as("api-token-wrong-code@example.com")
    user.update!(email_verified_at: Time.current)

    post send_code_api_token_url
    post confirm_api_token_url, params: { code: wrong_code_for(user) }, as: :json

    assert_response :forbidden

    post api_token_url, as: :json

    assert_response :forbidden
    assert_empty ApiToken.all
  end

  test "guessing the confirmation code burns it" do
    user = sign_in_as("api-token-guessed@example.com")
    user.update!(email_verified_at: Time.current)

    post send_code_api_token_url
    code = user.reload.login_code
    wrong = code == "0000" ? "1111" : "0000"

    ApiTokensController::MAX_CODE_ATTEMPTS.times do
      post confirm_api_token_url, params: { code: wrong }, as: :json
    end

    assert_nil user.reload.login_code

    post confirm_api_token_url, params: { code: code }, as: :json

    assert_response :forbidden

    post api_token_url, as: :json

    assert_response :forbidden
    assert_empty ApiToken.all
  end

  test "code delivery is limited per account across IPs and recovers after the window" do
    user = sign_in_as("api-token-delivery-account@example.com")
    user.update!(email_verified_at: Time.current)

    assert_enqueued_emails 3 do
      3.times do |index|
        post send_code_api_token_url, headers: { "REMOTE_ADDR" => "192.0.2.#{index + 1}" }, as: :json
        assert_response :accepted
      end
    end
    code = user.reload.login_code

    assert_no_enqueued_emails do
      post send_code_api_token_url, headers: { "REMOTE_ADDR" => "192.0.2.4" }, as: :json
      assert_response :too_many_requests
    end
    assert_equal code, user.reload.login_code

    travel 16.minutes do
      assert_enqueued_emails 1 do
        post send_code_api_token_url, as: :json
        assert_response :accepted
      end
    end
  end

  test "code delivery is limited per IP across accounts" do
    assert_enqueued_emails 10 do
      10.times do |index|
        user = sign_in_as("api-token-delivery-ip-#{index}@example.com")
        user.update!(email_verified_at: Time.current)
        post send_code_api_token_url, as: :json
        assert_response :accepted
      end
    end

    user = sign_in_as("api-token-delivery-ip-blocked@example.com")
    user.update!(email_verified_at: Time.current)
    assert_no_enqueued_emails do
      post send_code_api_token_url, as: :json
      assert_response :too_many_requests
    end
    assert_nil user.reload.login_code

    assert_enqueued_emails 1 do
      post send_code_api_token_url, headers: { "REMOTE_ADDR" => "192.0.2.20" }, as: :json
      assert_response :accepted
    end
  end

  test "interleaved confirmation failures still burn the code after five guesses" do
    user = sign_in_as("api-token-interleaved@example.com")
    user.update!(email_verified_at: Time.current)
    other_session = open_session
    other_session.post session_url, params: { email: user.email }
    post send_code_api_token_url
    wrong = wrong_code_for(user)
    interleaved = false

    # Второй запрос вклинивается после чтения старого счётчика либо после
    # атомарного increment: так потеря промаха воспроизводится без гонки потоков.
    observer = lambda do |_name, _start, _finish, _id, payload|
      if payload[:key] == "api_token_confirm_failures:#{user.id}" && !interleaved
        interleaved = true
        other_session.post confirm_api_token_url, params: { code: wrong }, as: :json
      end
    end

    ActiveSupport::Notifications.subscribed(observer, /cache_(read|increment)\.active_support/) do
      4.times { post confirm_api_token_url, params: { code: wrong }, as: :json }
    end

    assert interleaved
    assert_nil user.reload.login_code
  end

  test "signing out drops the confirmation" do
    user = sign_in_as("api-token-signed-out@example.com")
    user.update!(email_verified_at: Time.current)
    confirm_ownership(user)

    delete destroy_session_url
    post session_url, params: { email: user.email }

    post api_token_url, as: :json

    assert_response :forbidden
  end

  private

  def sign_in_as(email)
    post session_url, params: { email: email }
    User.find_by!(email: email)
  end

  def confirm_ownership(user)
    post send_code_api_token_url
    post confirm_api_token_url, params: { code: user.reload.login_code }
  end

  def wrong_code_for(user)
    user.reload.login_code == "0000" ? "1111" : "0000"
  end
end
