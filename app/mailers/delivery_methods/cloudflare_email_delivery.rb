require "json"
require "net/http"
require "uri"

module DeliveryMethods
  class CloudflareEmailDeliveryError < StandardError; end

  class CloudflareEmailDelivery
    API_BASE_URL = "https://api.cloudflare.com/client/v4/accounts".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    def initialize(settings)
      @account_id = settings[:account_id]
      @api_token = settings[:api_token]
      @default_from = settings[:from]
    end

    def deliver!(mail)
      ensure_configured!

      response = Net::HTTP.start(
        endpoint.host,
        endpoint.port,
        use_ssl: true,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) do |http|
        http.request(request(mail))
      end

      return response if response.is_a?(Net::HTTPSuccess) && cloudflare_success?(response)

      raise CloudflareEmailDeliveryError, "Cloudflare Email Sending failed: #{response.code} #{response.body}"
    end

    private

    def endpoint
      @endpoint ||= URI("#{API_BASE_URL}/#{@account_id}/email/sending/send")
    end

    def request(mail)
      Net::HTTP::Post.new(endpoint).tap do |request|
        request["Authorization"] = "Bearer #{@api_token}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload(mail))
      end
    end

    def payload(mail)
      {
        to: Array(mail.to),
        from: mail.from&.first || @default_from,
        subject: mail.subject,
        text: text_body(mail),
        html: html_body(mail)
      }.compact
    end

    def text_body(mail)
      return mail.text_part.decoded if mail.text_part

      mail.body.decoded if mail.mime_type == "text/plain"
    end

    def html_body(mail)
      return mail.html_part.decoded if mail.html_part

      mail.body.decoded if mail.mime_type == "text/html"
    end

    def ensure_configured!
      return if @account_id.present? && @api_token.present? && @default_from.present?

      raise CloudflareEmailDeliveryError, "Cloudflare Email Sending credentials are missing"
    end

    def cloudflare_success?(response)
      JSON.parse(response.body).fetch("success")
    rescue JSON::ParserError, KeyError
      false
    end
  end
end
