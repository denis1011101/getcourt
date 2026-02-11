module Telegram
  module Flows
    module Games
      module Manage
        module JoinFlow
          class << self
            def handle_callback(callback)
              cb = Telegram::Helpers::CallbackData.parse(callback)
              poller = Telegram::Poller.new

              case cb.data
              when /\Agame:join:(\d+)\z/
                game = Game.find_by(id: $1.to_i)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
                game_url = "#{host}/games/#{game&.id}"
                unless game && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Game or user not found", show_alert: false }) rescue nil
                  return
                end

                begin
                  participation = Participation.find_by(game: game, user: user)
                  direct_join = user.admin? || user.id == game.user_id

                  if participation
                    if participation.respond_to?(:pending?) && participation.pending?
                      if direct_join
                        participation.update(status: "approved", approved_at: Time.current) rescue nil
                        poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "You joined the game", show_alert: false }) rescue nil
                      else
                        poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Request already sent", show_alert: false }) rescue nil
                      end
                    else
                      poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "You already joined", show_alert: false }) rescue nil
                    end
                  else
                    if direct_join
                      Participation.create!(game: game, user: user, status: "approved", approved_at: Time.current) rescue nil
                      poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "You joined the game", show_alert: false }) rescue nil
                    else
                      participation = Participation.create!(game: game, user: user, status: "pending") rescue nil
                      poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Join request sent", show_alert: false }) rescue nil

                      owner_chat_id = game.user&.telegram_chat_id
                      if owner_chat_id.present?
                        requester = Telegram::Helpers::UserLookup.display_name(user)
                        buttons = [ [
                          { text: "Approve", callback_data: "game:approve_participation:#{participation.id}" },
                          { text: "Reject",  callback_data: "game:reject_participation:#{participation.id}" }
                        ] ]
                        poller.send_api("sendMessage", {
                          chat_id: owner_chat_id,
                          text: "Join request for Game ##{game.id} from #{requester}\n\n#{game_url}",
                          reply_markup: { inline_keyboard: buttons }
                        }) rescue nil
                      end
                    end
                  end
                rescue => e
                  Rails.logger.error "[Telegram::Flows::Games::Manage::JoinFlow] join error: #{e.class} #{e.message}"
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Failed to join the game", show_alert: true }) rescue nil
                end

                Telegram::Handlers::GamesHandler.show_game(cb.chat_id, game.id, 1, message_id: cb.message_id) rescue nil
                nil

              when /\Agame:join_invited:(\d+)\z/
                game = Game.find_by(id: $1.to_i)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless game && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Game or user not found", show_alert: false }) rescue nil
                  return
                end

                begin
                  participation = Participation.find_by(game: game, user: user)

                  if participation
                    if participation.respond_to?(:pending?) && participation.pending?
                      participation.update(status: "approved", approved_at: Time.current) rescue nil
                      poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "You joined the game", show_alert: false }) rescue nil
                    else
                      poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "You already joined", show_alert: false }) rescue nil
                    end
                  else
                    # Invited users are auto-approved without notifying the owner
                    Participation.create!(game: game, user: user, status: "approved", approved_at: Time.current) rescue nil
                    poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "You joined the game", show_alert: false }) rescue nil
                  end
                rescue => e
                  Rails.logger.error "[Telegram::Flows::Games::Manage::JoinFlow] join_invited error: #{e.class} #{e.message}"
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Failed to join the game", show_alert: true }) rescue nil
                end

                Telegram::Handlers::GamesHandler.show_game(cb.chat_id, game.id, 1, message_id: cb.message_id) rescue nil
                nil

              when /\Agame:leave:(\d+)\z/
                game = Game.find_by(id: $1.to_i)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless game && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Game or user not found", show_alert: false }) rescue nil
                  return
                end

                participation = Participation.find_by(game: game, user: user)
                unless participation
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "You are not a participant", show_alert: false }) rescue nil
                  Telegram::Handlers::GamesHandler.show_game(cb.chat_id, game.id, 1, message_id: cb.message_id) rescue nil
                  return
                end

                participation.destroy rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "You left the game", show_alert: false }) rescue nil
                Telegram::Handlers::GamesHandler.show_game(cb.chat_id, game.id, 1, message_id: cb.message_id) rescue nil
                nil

              when /\Agame:join_pending:(\d+)\z/
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Request is pending approval", show_alert: false }) rescue nil
                nil

              else
                nil
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::Manage::JoinFlow] #{e.class} #{e.message}"
              nil
            end
          end
        end
      end
    end
  end
end
