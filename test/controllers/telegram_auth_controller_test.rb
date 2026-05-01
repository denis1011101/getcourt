require "test_helper"
require "openssl"
require "uri"

class TelegramAuthControllerTest < ActionDispatch::IntegrationTest
  BOT_TOKEN = "123456:test-token"

  setup do
    @old_token = ENV["TELEGRAM_BOT_TOKEN"]
    ENV["TELEGRAM_BOT_TOKEN"] = BOT_TOKEN
  end

  teardown do
    ENV["TELEGRAM_BOT_TOKEN"] = @old_token
  end

  test "signs in connected user from valid Telegram WebApp initData" do
    user = User.create!(email: "telegram-web-app@example.org", telegram_chat_id: 12345)

    post telegram_web_app_auth_path,
         params: { init_data: signed_init_data(auth_date: Time.now.to_i, user: { id: 12345, username: "tester" }) },
         as: :json

    assert_response :success
    assert_equal({ "ok" => true }, response.parsed_body)
    assert_equal user.id, session[:user_id]
  end

  test "rejects valid Telegram WebApp initData for unconnected user" do
    post telegram_web_app_auth_path,
         params: { init_data: signed_init_data(auth_date: Time.now.to_i, user: { id: 54321 }) },
         as: :json

    assert_response :not_found
    assert_nil session[:user_id]
  end

  test "rejects expired Telegram WebApp initData" do
    post telegram_web_app_auth_path,
         params: { init_data: signed_init_data(auth_date: 2.days.ago.to_i, user: { id: 12345 }) },
         as: :json

    assert_response :unauthorized
    assert_nil session[:user_id]
  end

  private

  def signed_init_data(auth_date:, user:)
    params = {
      "auth_date" => auth_date.to_s,
      "user" => user.to_json
    }
    check_string = params.sort.map { |key, value| "#{key}=#{value}" }.join("\n")
    secret_key = OpenSSL::HMAC.digest("SHA256", "WebAppData", BOT_TOKEN)
    params["hash"] = OpenSSL::HMAC.hexdigest("SHA256", secret_key, check_string)
    URI.encode_www_form(params)
  end
end
