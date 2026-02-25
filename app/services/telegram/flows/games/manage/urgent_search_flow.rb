module Telegram
  module Flows
    module Games
      module Manage
        module UrgentSearchFlow
          class << self
            include Telegram::Handlers::ReplyHelpers

            def handle_callback(callback)
              cb = Telegram::Helpers::CallbackData.parse(callback)
              locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

              return nil unless cb.data =~ /\Agame:urgent_search:(\d+):(on|off):(\d+)\z/

              game_id = Regexp.last_match(1).to_i
              new_state = Regexp.last_match(2) == "on"
              page = Regexp.last_match(3).to_i

              game = Game.find_by(id: game_id)
              user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)

              unless game && user
                Telegram::Api.answer_callback(cb.cb_id, t.(:game_not_found), show_alert: true) rescue nil
                return nil
              end

              unless user.admin? || user.id == game.user_id
                Telegram::Api.answer_callback(cb.cb_id, t.(:no_permission), show_alert: true) rescue nil
                return nil
              end

              game.update!(urgent_player_search: new_state)
              Telegram::Api.answer_callback(cb.cb_id, t.(:field_updated)) rescue nil
              Telegram::Handlers::GamesHandler.show_game(cb.chat_id, game.id, page, message_id: cb.message_id)
              nil
            rescue => e
              Rails.logger.error "[UrgentSearchFlow] #{e.class}: #{e.message}"
              Telegram::Api.answer_callback(cb.cb_id, "Error", show_alert: true) rescue nil
              nil
            end
          end
        end
      end
    end
  end
end
