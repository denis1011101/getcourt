module Telegram
  module Handlers
    class CallbackHandler
      def self.process(callback_query)
        return true if Telegram::Handlers::MenuCallbackHandler.process(callback_query)
        return true if defined?(Telegram::Handlers::CallbackRouter) && Telegram::Handlers::CallbackRouter.route(callback_query)

        cb = Telegram::Helpers::CallbackData.parse(callback_query)
        return true if cb.data.match?(/\Atg_fill(?::|_)/) && (Telegram::Flows::StatsFlow.handle_callback(callback_query); true)
        return true unless cb.chat_id.present? && cb.data.present?

        locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
        t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

        case cb.data
        when /\A(?:menu:search|search:)/
          Telegram::Flows::SearchFlow.handle_callback(callback_query) rescue nil
          true

        when /\Aprofile:(.*)\z/
          Telegram::Flows::ProfileFlow.handle_callback(callback_query) rescue nil
          true

        when /\Atg_stats_locked:(\d+)\z/
          game = Game.find_by(id: Regexp.last_match(1).to_i)
          unless game
            Telegram::Api.answer_callback(cb.cb_id, t.(:game_not_found), show_alert: true) rescue nil
            return true
          end

          start_at = game.start_at_for_ui
          if start_at
            tz = game.creator_time_zone
            Telegram::Api.answer_callback(
              cb.cb_id,
              t.(:stats_locked_msg, time: start_at.strftime("%Y-%m-%d %H:%M"), tz: tz),
              show_alert: true
            ) rescue nil
          else
            Telegram::Api.answer_callback(cb.cb_id, t.(:stats_locked_no_time), show_alert: true) rescue nil
          end
          true

        when /\Atg_stats_unauthorized:(\d+)\z/
          Telegram::Api.answer_callback(cb.cb_id, t.(:stats_unauthorized), show_alert: true) rescue nil
          true

        when /\Atg_fill:(\d+)\z/
          game = Game.find_by(id: Regexp.last_match(1).to_i)
          unless game
            Telegram::Api.answer_callback(cb.cb_id, t.(:game_not_found), show_alert: true) rescue nil
            return true
          end

          user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
          unless user && (user.admin? || user.id == game.user_id)
            Telegram::Api.answer_callback(cb.cb_id, t.(:stats_unauthorized), show_alert: true) rescue nil
            return true
          end

          unless game.started_for_ui?
            start_at = game.start_at_for_ui
            tz = game.creator_time_zone
            msg = start_at ? t.(:stats_locked_msg, time: start_at.strftime("%Y-%m-%d %H:%M"), tz: tz) : t.(:stats_will_be_available)
            Telegram::Api.answer_callback(cb.cb_id, msg, show_alert: true) rescue nil
            return true
          end

          game_id = game.id
          key = Telegram::Helpers::Conversation.key(cb.chat_id)
          Rails.cache.write(key, { "game_id" => game_id, "step" => "singles_hours", "created_at" => Time.current }, expires_in: 2.hours)
          Telegram::Api.answer_callback(cb.cb_id) rescue nil
          Telegram::Api.send_force_reply(cb.chat_id, t.(:stats_reply_singles_hours)) rescue nil
          true

        when /\Atg_not_happened:(\d+)\z/
          game = Game.find_by(id: Regexp.last_match(1).to_i)
          unless game && game.user&.telegram_chat_id.to_i == cb.chat_id.to_i
            Telegram::Api.answer_callback(cb.cb_id, t.(:unauthorized_or_not_found), show_alert: true) rescue nil
            return
          end

          host = ENV.fetch("APP_HOST", "http://localhost:3000")
          signed = game.signed_id(expires_in: 7.days, purpose: "mark_not_happened")
          url = "#{Rails.application.routes.url_helpers.game_url(game, host: host)}?mark_not_happened=#{CGI.escape(signed)}"
          Telegram::Api.answer_callback(cb.cb_id) rescue nil
          Telegram::Api.send_with_buttons(cb.chat_id, t.(:mark_not_happened), [ { text: t.(:not_happened_btn), url: url } ]) rescue nil

        else
          Telegram::Api.answer_callback(cb.cb_id, t.(:unknown_action), show_alert: true) rescue nil
        end
      rescue => e
        Rails.logger.error("[Telegram::Handlers::CallbackHandler] #{e.class}: #{e.message}")
        cb_id = callback_query["id"] rescue nil
        Telegram::Api.answer_callback(cb_id, "Error", show_alert: true) rescue nil
      end
    end
  end
end
