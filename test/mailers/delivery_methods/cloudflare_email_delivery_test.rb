require "test_helper"

module DeliveryMethods
  class CloudflareEmailDeliveryTest < ActiveSupport::TestCase
    test "posts email to Cloudflare Email Sending API" do
      with_fake_http(success_response) do |captured|
        delivery.deliver!(mail)

        assert_equal "api.cloudflare.com", captured[:host]
        assert_equal 443, captured[:port]
        assert_equal true, captured[:options][:use_ssl]
        assert_equal 5, captured[:options][:open_timeout]
        assert_equal 10, captured[:options][:read_timeout]
        assert_equal "/client/v4/accounts/account-123/email/sending/send", captured[:request].path
        assert_equal "Bearer token-123", captured[:request]["Authorization"]
        assert_equal "application/json", captured[:request]["Content-Type"]

        body = JSON.parse(captured[:request].body)
        assert_equal [ "to@example.org" ], body["to"]
        assert_equal "no-reply@getcourt.co", body["from"]
        assert_equal "Subject", body["subject"]
        assert_equal "Plain body", body["text"]
        assert_equal "<p>HTML body</p>", body["html"]
      end
    end

    test "raises when Cloudflare returns success false" do
      with_fake_http(success_response(body: { success: false, errors: [ { message: "nope" } ] }.to_json)) do
        assert_raises(CloudflareEmailDeliveryError) { delivery.deliver!(mail) }
      end
    end

    test "raises on non-success HTTP response" do
      with_fake_http(response(Net::HTTPBadRequest, "400", { success: false }.to_json)) do
        assert_raises(CloudflareEmailDeliveryError) { delivery.deliver!(mail) }
      end
    end

    private

    def delivery
      CloudflareEmailDelivery.new(
        account_id: "account-123",
        api_token: "token-123",
        from: "no-reply@getcourt.co"
      )
    end

    def mail
      Mail.new do
        to "to@example.org"
        from "no-reply@getcourt.co"
        subject "Subject"
        text_part { body "Plain body" }
        html_part do
          content_type "text/html"
          body "<p>HTML body</p>"
        end
      end
    end

    def success_response(body: { success: true, errors: [], messages: [], result: {} }.to_json)
      response(Net::HTTPOK, "200", body)
    end

    def response(klass, code, body)
      klass.new("1.1", code, "OK").tap do |response|
        response.define_singleton_method(:body) { body }
      end
    end

    def with_fake_http(response)
      captured = {}
      original_start = Net::HTTP.method(:start)

      Net::HTTP.define_singleton_method(:start) do |host, port, **options, &block|
        http = Object.new

        http.define_singleton_method(:request) do |request|
          captured[:request] = request
          response
        end

        captured[:host] = host
        captured[:port] = port
        captured[:options] = options
        block.call(http)
      end

      yield captured
    ensure
      Net::HTTP.define_singleton_method(:start, original_start)
    end
  end
end
