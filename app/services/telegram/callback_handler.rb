module Telegram
  class CallbackHandler
    def self.handle(callback_query)
      data = callback_query["data"].to_s
      callback_id = callback_query["id"]
      from = callback_query["from"] || {}
      chat_id = callback_query.dig("message","chat","id") || from["id"]

      case
      when data.start_with?("tg_fill:")
        game_id = data.split(":",2).last
        key = conv_key(chat_id)
        Rails.cache.write(key, { "game_id" => game_id, "step" => "ask_singles_hours", "created_at" => Time.current }, expires_in: 2.hours)
        Api.answer_callback(callback_id)
        Api.send_force_reply(chat_id, "Please reply with singles hours (example: 1.5).")
      when data.start_with?("tg_not_happened:")
        signed = data.split(":",2).last
        Api.answer_callback(callback_id, "Processing...", show_alert: false)
        begin
          game = Game.find_signed(signed, purpose: "mark_not_happened")
          if game
            # implement your business logic for marking as not happened
            game.update!(players_count: 0) if game.respond_to?(:players_count)
            Api.send_simple(chat_id, "Thanks — the game has been marked as not happened.")
          else
            Api.send_simple(chat_id, "Link expired or game not found.")
          end
        rescue => e
          Rails.logger.error "[Telegram::CallbackHandler] #{e.class} #{e.message}"
          Api.send_simple(chat_id, "An error occurred while marking the game.")
        end
      else
        Api.answer_callback(callback_id)
      end
    end

    def self.conv_key(chat_id)
      "tg:conv:#{chat_id}"
    end
  end
end
