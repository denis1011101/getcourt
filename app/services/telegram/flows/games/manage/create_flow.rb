module Telegram
  module Flows
    module Games
      module Manage
        module CreateFlow
          class << self
            def handle_callback(callback)
              cb = Telegram::Helpers::CallbackData.parse(callback)
              poller = Telegram::Poller.new
              locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

              case cb.data
              when /\Agame:create:field:(\w+):(\d+)\z/
                Telegram::Flows::Games::EditPrompter.handle_callback(callback) rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                nil

              when /\Agame:create:confirm:(\d+)\z/
                gid = $1.to_i
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                Telegram::Handlers::GamesHandler.show_game(cb.chat_id, gid, 1, message_id: cb.message_id) rescue nil
                nil

              when /\Agame:create:cancel:(\d+)(?::(\d+))?\z/
                gid = $1.to_i
                orig_msg_id = $2 ? $2.to_i : nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:create_game_cancelled), show_alert: false }) rescue nil
                begin
                  game = Game.find_by(id: gid)
                  if game
                    court_id = game.court_id
                    game.destroy rescue nil
                    if orig_msg_id && court_id
                      Telegram::Handlers::CourtsHandler.show_court(cb.chat_id, court_id, 1, message_id: orig_msg_id) rescue nil
                    end
                  end
                rescue => e
                  Rails.logger.error "[Telegram::Flows::Games::Manage::CreateFlow] cancel error: #{e.class} #{e.message}"
                end
                nil

              when /\Agame:create\z/
                start_create_game(cb.chat_id, cb_id: cb.cb_id)
                nil

              else
                nil
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::Manage::CreateFlow] #{e.class} #{e.message}"
              nil
            end

            def start_create_game(chat_id, cb_id: nil)
              locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

              poller = Telegram::Poller.new
              user = Telegram::Helpers::UserLookup.find_user(chat_id)
              if user
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: t.(:create_game_reply), show_alert: false }) rescue nil
                poller.send_api("sendMessage", {
                  chat_id: chat_id,
                  text: "GAME_PROMPT\n#{t.(:create_game_prompt)}",
                  reply_markup: { force_reply: true, selective: true }
                }) rescue nil
              else
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: t.(:no_linked_account), show_alert: false }) rescue nil
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::Manage::CreateFlow] start_create_game error: #{e.class} #{e.message}"
              nil
            end
          end
        end
      end
    end
  end
end
