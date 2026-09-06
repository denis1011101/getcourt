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

    post api_token_url

    assert_redirected_to security_account_path

    get security_account_url

    assert_response :success
    assert_includes response.body, user.api_tokens.active.first.token
  end

  private

  def sign_in_as(email)
    post session_url, params: { email: email }
    User.find_by!(email: email)
  end
end
