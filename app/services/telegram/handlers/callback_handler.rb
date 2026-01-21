module Telegram
  module Handlers
    class CallbackHandler
      def self.process(callback_query)
        return true if Telegram::Handlers::MenuCallbackHandler.process(callback_query)
        # route to dedicated handlers first
        return true if defined?(Telegram::Handlers::CallbackRouter) && Telegram::Handlers::CallbackRouter.route(callback_query)

        data = callback_query["data"].to_s
        callback_id = callback_query["id"]
        from = callback_query["from"] || {}
        chat_id = callback_query.dig("message", "chat", "id") || from["id"]
        return true unless chat_id && data.present?

        case data
        when /\A(?:menu:search|search:)/
          Rails.logger.info "[Telegram::Handlers::CallbackHandler] routing search callback: #{data.inspect} chat_id=#{chat_id}"
          Telegram::Flows::SearchFlow.handle_callback(callback_query) rescue (Rails.logger.error "[Telegram::Handlers::CallbackHandler] search routing failed: #{$!.class}: #{$!.message}")
          return true
        when /\Aprofile:(.*)\z/
          Rails.logger.info "[Telegram::Handlers::CallbackHandler] routing profile callback: #{data.inspect} chat_id=#{chat_id}"
          Telegram::Flows::ProfileFlow.handle_callback(callback_query) rescue (Rails.logger.error "[Telegram::Handlers::CallbackHandler] profile routing failed: #{$!.class}: #{$!.message}"; nil)
          return true
        when /\Atg_fill:(\d+)\z/
          game_id = Regexp.last_match(1).to_i
          key = conv_key(chat_id)
          Rails.cache.write(key, { "game_id" => game_id, "step" => "singles_hours", "created_at" => Time.current }, expires_in: 2.hours)
          Telegram::Api.answer_callback(callback_id) rescue nil
          Telegram::Api.send_force_reply(chat_id, "Please reply with singles hours (example: 1.5) or type 'skip'") rescue nil

        when /\Atg_not_happened:(\d+)\z/
          game = Game.find_by(id: Regexp.last_match(1).to_i)
          unless game && game.user&.telegram_chat_id.to_i == chat_id.to_i
            Telegram::Api.answer_callback(callback_id, "Unauthorized or game not found.", show_alert: true) rescue nil
            return
          end

          host = ENV.fetch("APP_HOST", "http://localhost:3000")
          signed = game.signed_id(expires_in: 7.days, purpose: "mark_not_happened")
          url = "#{Rails.application.routes.url_helpers.game_url(game, host: host)}?mark_not_happened=#{CGI.escape(signed)}"
          Telegram::Api.answer_callback(callback_id) rescue nil
          Telegram::Api.send_with_buttons(chat_id, "Mark game as not happened (use the button):", [{ text: "Mark as not happened", url: url }]) rescue nil

        else
          Telegram::Api.answer_callback(callback_id, "Unknown action.", show_alert: true) rescue nil
        end
      rescue => e
        Rails.logger.error("[Telegram::Handlers::CallbackHandler] #{e.class}: #{e.message}")
        Telegram::Api.answer_callback(callback_id, "Callback processing error.", show_alert: true) rescue nil
      end

      def self.conv_key(chat_id)
        "tg:conv:#{chat_id}"
      end
    end
  end
end
