module Telegram
  module Flows
    module Games
      module Manage
        module DeleteFlow
          class << self
            include Telegram::Handlers::ReplyHelpers

            def handle_callback(callback)
              cb = Telegram::Helpers::CallbackData.parse(callback)
              poller = Telegram::Poller.new

              case cb.data
              when /\Agame:delete:(\d+)(?::(\d+))?\z/
                game_id = $1.to_i
                page = ($2 || 1).to_i

                game = Game.find_by(id: game_id)
                unless game
                  send_or_edit_text(cb.chat_id, "Game not found.", message_id: cb.message_id)
                  return
                end

                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless user && (user.admin? || user.id == game.user_id)
                  send_or_edit_text(cb.chat_id, "No permission to delete this game.", message_id: cb.message_id)
                  return
                end

                game.destroy rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                Telegram::Handlers::GamesHandler.list_page(cb.chat_id, page, message_id: cb.message_id) rescue nil
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
