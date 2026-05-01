require "openssl"
require "uri"

module Telegram
  class WebAppAuth
    MAX_AGE = 86_400

    def self.verify(init_data, bot_token)
      params = URI.decode_www_form(init_data.to_s).to_h
      hash = params.delete("hash")
      return nil if hash.blank? || bot_token.blank?

      auth_date = params["auth_date"].to_i
      return nil if auth_date <= 0 || Time.now.to_i - auth_date > MAX_AGE

      check_string = params.sort.map { |key, value| "#{key}=#{value}" }.join("\n")
      secret_key = OpenSSL::HMAC.digest("SHA256", "WebAppData", bot_token)
      computed = OpenSSL::HMAC.hexdigest("SHA256", secret_key, check_string)
      return nil unless ActiveSupport::SecurityUtils.secure_compare(computed, hash)

      params
    rescue ArgumentError
      nil
    end
  end
end
