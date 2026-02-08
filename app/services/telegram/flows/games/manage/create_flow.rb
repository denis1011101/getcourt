module Telegram
  module Flows
    module Games
      module Manage
        module CreateFlow
          class << self
            def handle_callback(callback)
              data = (callback["data"] || "").to_s
              cb_id = callback["id"]
              from = callback["from"] || {}
              chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
              message_id = callback.dig("message", "message_id")
              poller = Telegram::Poller.new

              case data
              when /\Agame:create:field:(\w+):(\d+)\z/
                Telegram::Flows::Games::EditPrompter.handle_callback(callback) rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
                nil

              when /\Agame:create:confirm:(\d+)\z/
                gid = $1.to_i
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
                Telegram::Handlers::GamesHandler.show_game(chat_id, gid, 1, message_id: message_id) rescue nil
                nil

              when /\Agame:create:cancel:(\d+)(?::(\d+))?\z/
                gid = $1.to_i
                orig_msg_id = $2 ? $2.to_i : nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Create cancelled", show_alert: false }) rescue nil
                begin
                  game = Game.find_by(id: gid)
                  if game
                    court_id = game.court_id
                    game.destroy rescue nil
                    if orig_msg_id && court_id
                      Telegram::Handlers::CourtsHandler.show_court(chat_id, court_id, 1, message_id: orig_msg_id) rescue nil
                    end
                  end
                rescue => e
                  Rails.logger.error "[Telegram::Flows::Games::Manage::CreateFlow] cancel error: #{e.class} #{e.message}"
                end
                nil

              when /\Agame:create\z/
                start_create_game(chat_id, cb_id: cb_id)
                nil

              else
                nil
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::Manage::CreateFlow] #{e.class} #{e.message}"
              nil
            end

            def start_create_game(chat_id, cb_id: nil)
              poller = Telegram::Poller.new
              user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
              if user
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Create game — reply with details", show_alert: false }) rescue nil
                poller.send_api("sendMessage", {
                  chat_id: chat_id,
                  text: "GAME_PROMPT\nReply with: date(YYYY-MM-DD) time(HH:MM) players_count sport [court_id]\nExample:\n2025-12-10 19:00 4 tennis 12",
                  reply_markup: { force_reply: true, selective: true }
                }) rescue nil
              else
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No linked account. Send /start first.", show_alert: false }) rescue nil
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
