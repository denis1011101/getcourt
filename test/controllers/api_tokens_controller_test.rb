require "test_helper"

class ApiTokensControllerTest < ActionDispatch::IntegrationTest
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

  # Счётчик промахов живёт в кэше, а в тестовой среде это :null_store, поэтому
  # на время теста подменяем хранилище.
  test "guessing the confirmation code burns it" do
    previous_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
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
  ensure
    Rails.cache = previous_store
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
