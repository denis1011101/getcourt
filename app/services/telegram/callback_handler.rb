module Telegram
  class CallbackHandler
    def self.handle(callback_query)
      data = callback_query["data"].to_s
      callback_id = callback_query["id"]
      from = callback_query["from"] || {}
      chat_id = callback_query.dig("message", "chat", "id") || from["id"]
      return unless chat_id && data.present?

      case data
      when /\Atg_fill:(\d+)\z/
        game_id = Regexp.last_match(1).to_i
        key = conv_key(chat_id)
        Rails.cache.write(key, { "game_id" => game_id, "step" => "singles_hours", "created_at" => Time.current }, expires_in: 2.hours)
        Api.answer_callback(callback_id) rescue nil
        Api.send_force_reply(chat_id, "Please reply with singles hours (example: 1.5) or type 'skip'") rescue nil

      when /\Atg_not_happened:(\d+)\z/
        game = Game.find_by(id: Regexp.last_match(1).to_i)
        unless game && game.user&.telegram_chat_id.to_i == chat_id.to_i
          Api.answer_callback(callback_id, "Unauthorized or game not found.", show_alert: true) rescue nil
          return
        end

        host = ENV.fetch("APP_HOST", "http://localhost:3000")
        signed = game.signed_id(expires_in: 7.days, purpose: "mark_not_happened")
        url = "#{Rails.application.routes.url_helpers.game_url(game, host: host)}?mark_not_happened=#{CGI.escape(signed)}"
        Api.answer_callback(callback_id) rescue nil
        Api.send_with_buttons(chat_id, "Mark game as not happened (use the button):", [{ text: "Mark as not happened", url: url }]) rescue nil

      else
        Api.answer_callback(callback_id, "Unknown action.", show_alert: true) rescue nil
      end
    rescue => e
      Rails.logger.error("[Telegram::CallbackHandler] #{e.class}: #{e.message}")
      Api.answer_callback(callback_id, "Callback processing error.", show_alert: true) rescue nil
    end

    def self.conv_key(chat_id)
      "tg:conv:#{chat_id}"
    end
  end
end
