require "net/http"
require "json"

module Telegram
  class Poller
    API_ROOT = ->(token) { "https://api.telegram.org/bot#{token}" }

    def initialize(token: ENV["TELEGRAM_BOT_TOKEN"])
      @token = token.to_s
      raise "TELEGRAM_BOT_TOKEN not set" if @token.strip.empty?
      @api = API_ROOT.call(@token)
      @offset = nil
    end

    # Run single poll iteration (useful for tests)
    def run_once
      uri = URI("#{@api}/getUpdates")
      params = { timeout: 0 }
      params[:offset] = @offset if @offset
      uri.query = URI.encode_www_form(params)

      res = Net::HTTP.get_response(uri)
      return unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body) rescue {}
      (data["result"] || []).each do |update|
        process_update(update)
        @offset = update["update_id"].to_i + 1
      end
    rescue => e
      Rails.logger.error "Telegram poll error: #{e.class} #{e.message}"
    end

    # Blocking loop (run locally)
    def run_loop(poll_interval: 1)
      loop do
        run_once
        sleep poll_interval
      end
    end

    private

    # Duplicate small part of BotWebhookController logic to handle /register commands
    def process_update(update)
      message = update["message"] || {}
      chat = message["chat"] || {}
      text = message["text"].to_s.strip

      if text =~ %r{\A/register\s+([0-9a-fA-F]+)\z}i
        token = $1
        user = User.find_by(telegram_registration_token: token)
        if user && chat["id"]
          chat_id = chat["id"].to_s
          User.transaction do
            User.where(telegram_chat_id: chat_id).where.not(id: user.id).update_all(telegram_chat_id: nil)
            user.update!(telegram_chat_id: chat_id)
            user.clear_telegram_registration_token! rescue nil
          end
          TelegramNotifier.send_message(chat_id, "Registration complete. You will receive notifications here.")
        else
          TelegramNotifier.send_message(chat["id"], "Invalid or expired token.") if chat["id"]
        end
      end
    rescue => e
      Rails.logger.error "Telegram.process_update error: #{e.class} #{e.message}"
    end
  end
end
