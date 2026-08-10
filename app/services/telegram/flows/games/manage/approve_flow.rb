module Telegram
  module Flows
    module Games
      module Manage
        module ApproveFlow
          class << self
            def handle_callback(callback)
              cb = Telegram::Helpers::CallbackData.parse(callback)
              poller = Telegram::Poller.new
              locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

              case cb.data
              when /\Agame:approve_participation:(\d+)\z/
                participation = Participation.find_by(id: $1.to_i)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless participation && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:participation_request_not_found), show_alert: false }) rescue nil
                  return
                end

                game = participation.game
                unless user.admin? || user.id == game.user_id
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:participation_no_permission), show_alert: true }) rescue nil
                  return
                end

                participation.update(status: "approved", approved_at: Time.current) rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:participation_approved), show_alert: false }) rescue nil

                if cb.message_id && cb.chat_id
                  begin
                    poller.send_api("editMessageText", {
                      chat_id: cb.chat_id,
                      message_id: cb.message_id,
                      text: t.(:user_accepted),
                      reply_markup: { inline_keyboard: [] }
                    })
                  rescue => e
                    Rails.logger.error "[Telegram::Flows::Games::Manage::ApproveFlow] editMessageText failed: #{e.class} #{e.message}"
                  end
                end

                GameRequestNotification.participation(user: participation.user, game: game, approved: true)

                nil

              when /\Agame:reject_participation:(\d+)\z/
                participation = Participation.find_by(id: $1.to_i)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless participation && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:participation_request_not_found), show_alert: false }) rescue nil
                  return
                end

                game = participation.game
                unless user.admin? || user.id == game.user_id
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:participation_no_permission), show_alert: true }) rescue nil
                  return
                end

                requester = participation.user
                participation.destroy rescue nil
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:participation_rejected), show_alert: false }) rescue nil

                if cb.message_id && cb.chat_id
                  begin
                    poller.send_api("editMessageText", {
                      chat_id: cb.chat_id,
                      message_id: cb.message_id,
                      text: t.(:user_rejected),
                      reply_markup: { inline_keyboard: [] }
                    })
                  rescue => e
                    Rails.logger.error "[Telegram::Flows::Games::Manage::ApproveFlow] editMessageText failed: #{e.class} #{e.message}"
                  end
                end

                GameRequestNotification.participation(user: requester, game: game, approved: false)

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
