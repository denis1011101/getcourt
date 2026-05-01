require "test_helper"
require "openssl"
require "uri"

module Telegram
  class WebAppAuthTest < ActiveSupport::TestCase
    BOT_TOKEN = "123456:test-token"

    test "verifies signed init data" do
      init_data = signed_init_data(auth_date: Time.now.to_i, user: { id: 12345, username: "tester" })

      params = Telegram::WebAppAuth.verify(init_data, BOT_TOKEN)

      assert_equal "12345", JSON.parse(params["user"])["id"].to_s
      assert_equal "tester", JSON.parse(params["user"])["username"]
    end

    test "rejects expired init data" do
      init_data = signed_init_data(auth_date: 2.days.ago.to_i, user: { id: 12345 })

      assert_nil Telegram::WebAppAuth.verify(init_data, BOT_TOKEN)
    end

    test "rejects tampered init data" do
      init_data = signed_init_data(auth_date: Time.now.to_i, user: { id: 12345 })

      assert_nil Telegram::WebAppAuth.verify(init_data.sub("12345", "99999"), BOT_TOKEN)
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
end
