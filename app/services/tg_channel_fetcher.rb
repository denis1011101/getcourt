require "tdlib-ruby"
require "json"
require "net/http"
require "uri"

class TgChannelFetcher
  def self.run!
    TD.configure do |cfg|
      cfg.lib_path = ENV.fetch("TDLIB_LIB_PATH", Rails.root.join("vendor").to_s)
      cfg.client.api_id   = ENV.fetch("TELEGRAM_API_ID")
      cfg.client.api_hash = ENV.fetch("TELEGRAM_API_HASH")
      cfg.client.system_language_code = "en"
      cfg.client.database_directory = ENV.fetch("TDLIB_DB_DIR", "./.tdlib_db")
    end

    client = TD::Client.new
    client.connect

    state = nil
    client.on(TD::Types::Update::AuthorizationState) { |u| state = u.authorization_state }

    start = Time.now
    loop do
      break if state.is_a?(TD::Types::AuthorizationState::Ready)

      case state
      when TD::Types::AuthorizationState::WaitPhoneNumber
        raise "NON_INTERACTIVE auth" if ENV["NON_INTERACTIVE"]
        print "Phone: "
        client.set_authentication_phone_number(phone_number: STDIN.gets.strip, settings: nil).wait
      when TD::Types::AuthorizationState::WaitCode
        raise "NON_INTERACTIVE auth" if ENV["NON_INTERACTIVE"]
        print "Code: "
        client.check_authentication_code(code: STDIN.gets.strip).wait
      when TD::Types::AuthorizationState::WaitPassword
        raise "NON_INTERACTIVE auth" if ENV["NON_INTERACTIVE"]
        print "2FA password: "
        client.check_authentication_password(password: STDIN.gets.strip).wait
      end

      sleep 0.1
      raise "Auth timeout" if Time.now - start > 60 && !ENV["NON_INTERACTIVE"]
    end

    channels = (ENV["TELEGRAM_CHANNELS"] || "").split(",").map { |s| s.strip.sub(/^@/, "") }
    rails_url = ENV.fetch("RAILS_API_URL", "http://127.0.0.1:3000")
    rails_token = ENV["RAILS_API_TOKEN"]

    channels.each do |username|
      begin
        chat = client.search_public_chat(username) rescue nil
        next unless chat
        chat_id = chat.id

        history = client.get_chat_history(chat_id: chat_id, limit: 200) rescue nil
        messages_arr =
          if history.respond_to?(:messages)
            history.messages
          elsif history.is_a?(Array)
            history
          else
            []
          end

        uri = URI("#{rails_url}/api/telegram_posts")
        messages_arr.each do |m|
          msg = {
            channel_username: username,
            message_id: m.id,
            date: m.date,
            text: (m.respond_to?(:content) ? m.content.to_s : nil),
            raw: (m.to_h rescue {}) # <-- FIX: скобки
          }

          req = Net::HTTP::Post.new(uri)
          req["Content-Type"] = "application/json"
          req["X-API-TOKEN"] = rails_token if rails_token
          req.body = msg.to_json

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
        end
      rescue => e
        warn "fetch #{username} failed: #{e.class} #{e.message}"
      end
    end
  ensure
    client&.dispose
  end
end
