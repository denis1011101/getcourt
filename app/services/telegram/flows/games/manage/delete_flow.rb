module Telegram
  module Flows
    module Games
      module Manage
        module DeleteFlow
          class << self
            def handle_callback(callback)
              data = (callback["data"] || "").to_s
              cb_id = callback["id"]
              from = callback["from"] || {}
              chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
              message_id = callback.dig("message", "message_id")
              poller = Telegram::Poller.new

              case data
              when /\Agame:delete:(\d+)(?::(\d+))?\z/
                game_id = $1.to_i
                page = ($2 || 1).to_i

                game = Game.find_by(id: game_id)
                unless game
                  if message_id
                    Telegram::Api.edit_message_text(chat_id, message_id, "Game not found.") rescue nil
                  else
                    poller.send_api("sendMessage", { chat_id: chat_id, text: "Game not found." }) rescue nil
                  end
                  return
                end

                user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
                unless user && (user.admin? || user.id == game.user_id)
                  if message_id
                    Telegram::Api.edit_message_text(chat_id, message_id, "No permission to delete this game.") rescue nil
                  else
                    poller.send_api("sendMessage", { chat_id: chat_id, text: "No permission to delete this game." }) rescue nil
                  end
                  return
                end

                game.destroy rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
                Telegram::Handlers::GamesHandler.list_page(chat_id, page, message_id: message_id) rescue nil
                nil
              else
                nil
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::Manage::DeleteFlow] #{e.class} #{e.message}"
              nil
            end
          end
        end
      end
    end
  end
end
