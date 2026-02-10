module Telegram
  module Flows
    module Games
      module Manage
        module ApproveFlow
          class << self
            def handle_callback(callback)
              cb = Telegram::Helpers::CallbackData.parse(callback)
              poller = Telegram::Poller.new

              case cb.data
              when /\Agame:approve_participation:(\d+)\z/
                participation = Participation.find_by(id: $1.to_i)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless participation && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Request not found", show_alert: false }) rescue nil
                  return
                end

                game = participation.game
                unless user.admin? || user.id == game.user_id
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "No permission", show_alert: true }) rescue nil
                  return
                end

                participation.update(status: "approved", approved_at: Time.current) rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Approved", show_alert: false }) rescue nil

                if cb.message_id && cb.chat_id
                  begin
                    poller.send_api("editMessageText", {
                      chat_id: cb.chat_id,
                      message_id: cb.message_id,
                      text: "User accepted",
                      reply_markup: { inline_keyboard: [] }
                    })
                  rescue => e
                    Rails.logger.error "[Telegram::Flows::Games::Manage::ApproveFlow] editMessageText failed: #{e.class} #{e.message}"
                  end
                end

                if participation.user&.telegram_chat_id.present?
                  Telegram::Api.send_simple(participation.user.telegram_chat_id, "Your request to join Game ##{game.id} was approved.") rescue nil
                end

                nil

              when /\Agame:reject_participation:(\d+)\z/
                participation = Participation.find_by(id: $1.to_i)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless participation && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Request not found", show_alert: false }) rescue nil
                  return
                end

                game = participation.game
                unless user.admin? || user.id == game.user_id
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "No permission", show_alert: true }) rescue nil
                  return
                end

                participation.destroy rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Rejected", show_alert: false }) rescue nil

                if cb.message_id && cb.chat_id
                  begin
                    poller.send_api("editMessageText", {
                      chat_id: cb.chat_id,
                      message_id: cb.message_id,
                      text: "User rejected",
                      reply_markup: { inline_keyboard: [] }
                    })
                  rescue => e
                    Rails.logger.error "[Telegram::Flows::Games::Manage::ApproveFlow] editMessageText failed: #{e.class} #{e.message}"
                  end
                end

                if participation.user&.telegram_chat_id.present?
                  Telegram::Api.send_simple(participation.user.telegram_chat_id, "Your request to join Game ##{game.id} was rejected.") rescue nil
                end

                nil

              else
                nil
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::Manage::ApproveFlow] #{e.class} #{e.message}"
              nil
            end
          end
        end
      end
    end
  end
end
