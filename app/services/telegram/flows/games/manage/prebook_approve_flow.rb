module Telegram
  module Flows
    module Games
      module Manage
        module PrebookApproveFlow
          class << self
            def handle_callback(callback)
              data = (callback["data"] || "").to_s
              cb_id = callback["id"]
              from = callback["from"] || {}
              chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
              locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
              message_id = callback.dig("message", "message_id")
              poller = Telegram::Poller.new

              case data
              when /\Agame:approve_prebooking:(\d+)\z/
                prebooking = Prebooking.find_by(id: $1.to_i)
                user = User.find_by(telegram_chat_id: chat_id.to_s)
                unless prebooking && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_request_not_found, locale: locale), show_alert: false }) rescue nil
                  return
                end

                game = prebooking.game
                unless user.admin? || user.id == game.user_id
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_no_permission, locale: locale), show_alert: true }) rescue nil
                  return
                end

                unless prebooking.pending?
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_already_processed, locale: locale), show_alert: false }) rescue nil
                  return
                end

                prebooking.update!(status: "approved", approved_at: Time.current)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_approved, locale: locale), show_alert: false }) rescue nil

                update_notification_message(poller, chat_id, message_id, prebooking.id, "approved")

                if prebooking.user&.telegram_chat_id.present?
                  target_locale = Telegram::Helpers::UserLookup.locale_for(prebooking.user.telegram_chat_id)
                  Telegram::Api.send_simple(
                    prebooking.user.telegram_chat_id,
                    Telegram::I18n.t(
                      :prebook_user_approved,
                      locale: target_locale,
                      game_id: game.id,
                      date: prebooking.date.strftime("%Y-%m-%d")
                    )
                  ) rescue nil
                end

                nil

              when /\Agame:reject_prebooking:(\d+)\z/
                prebooking = Prebooking.find_by(id: $1.to_i)
                user = User.find_by(telegram_chat_id: chat_id.to_s)
                unless prebooking && user
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_request_not_found, locale: locale), show_alert: false }) rescue nil
                  return
                end

                game = prebooking.game
                unless user.admin? || user.id == game.user_id
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_no_permission, locale: locale), show_alert: true }) rescue nil
                  return
                end

                unless prebooking.pending?
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_already_processed, locale: locale), show_alert: false }) rescue nil
                  return
                end

                rejected_user = prebooking.user
                prebooking.update!(user: nil, status: "approved", approved_at: nil)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_rejected, locale: locale), show_alert: false }) rescue nil

                update_notification_message(poller, chat_id, message_id, prebooking.id, "rejected")

                if rejected_user&.telegram_chat_id.present?
                  target_locale = Telegram::Helpers::UserLookup.locale_for(rejected_user.telegram_chat_id)
                  Telegram::Api.send_simple(
                    rejected_user.telegram_chat_id,
                    Telegram::I18n.t(
                      :prebook_user_rejected,
                      locale: target_locale,
                      game_id: game.id,
                      date: prebooking.date.strftime("%Y-%m-%d")
                    )
                  ) rescue nil
                end

                nil

              when /\Agame:approve_all_prebookings:(\d+):(\d+)\z/
                game_id = $1.to_i
                user_id = $2.to_i

                game = Game.find_by(id: game_id)
                user = User.find_by(telegram_chat_id: chat_id.to_s)
                requester = User.find_by(id: user_id)

                unless user && game && (user.admin? || user.id == game.user_id)
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_no_permission, locale: locale), show_alert: true }) rescue nil
                  return
                end

                pending_prebookings = Prebooking.where(game_id: game_id, user_id: user_id, status: "pending")

                if pending_prebookings.empty?
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_no_pending, locale: locale), show_alert: false }) rescue nil
                  return
                end

                pending_prebookings.each do |pb|
                  pb.update!(status: "approved", approved_at: Time.current)
                end

                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_all_approved, locale: locale), show_alert: false }) rescue nil

                if message_id && chat_id
                  dates_text = pending_prebookings.map { |pb| pb.date.strftime("%Y-%m-%d") }.sort.join(", ")
                  host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
                  game_url = "#{host}/games/#{game.id}"
                  poller.send_api("editMessageText", {
                    chat_id: chat_id,
                    message_id: message_id,
                    text: Telegram::I18n.t(
                      :prebook_owner_all_approved_text,
                      locale: locale,
                      game_id: game.id,
                      dates: dates_text,
                      url: game_url
                    ),
                    reply_markup: { inline_keyboard: [] }
                  }) rescue nil
                end

                if requester&.telegram_chat_id.present?
                  requester_locale = Telegram::Helpers::UserLookup.locale_for(requester.telegram_chat_id)
                  dates_text = pending_prebookings.map { |pb| pb.date.strftime("%Y-%m-%d") }.sort.join(", ")
                  host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
                  game_url = "#{host}/games/#{game.id}"
                  Telegram::Api.send_simple(
                    requester.telegram_chat_id,
                    Telegram::I18n.t(
                      :prebook_requester_all_approved,
                      locale: requester_locale,
                      game_id: game.id,
                      dates: dates_text,
                      url: game_url
                    )
                  ) rescue nil
                end

                nil

              when /\Agame:reject_all_prebookings:(\d+):(\d+)\z/
                game_id = $1.to_i
                user_id = $2.to_i

                game = Game.find_by(id: game_id)
                user = User.find_by(telegram_chat_id: chat_id.to_s)
                requester = User.find_by(id: user_id)

                unless user && game && (user.admin? || user.id == game.user_id)
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_no_permission, locale: locale), show_alert: true }) rescue nil
                  return
                end

                pending_prebookings = Prebooking.where(game_id: game_id, user_id: user_id, status: "pending")

                if pending_prebookings.empty?
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_no_pending, locale: locale), show_alert: false }) rescue nil
                  return
                end

                dates_text = pending_prebookings.map { |pb| pb.date.strftime("%Y-%m-%d") }.sort.join(", ")

                pending_prebookings.each do |pb|
                  pb.update!(user_id: nil, status: "approved", approved_at: nil)
                end

                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: Telegram::I18n.t(:prebook_all_rejected, locale: locale), show_alert: false }) rescue nil

                if message_id && chat_id
                  host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
                  game_url = "#{host}/games/#{game.id}"
                  poller.send_api("editMessageText", {
                    chat_id: chat_id,
                    message_id: message_id,
                    text: Telegram::I18n.t(
                      :prebook_owner_all_rejected_text,
                      locale: locale,
                      game_id: game.id,
                      dates: dates_text,
                      url: game_url
                    ),
                    reply_markup: { inline_keyboard: [] }
                  }) rescue nil
                end

                if requester&.telegram_chat_id.present?
                  requester_locale = Telegram::Helpers::UserLookup.locale_for(requester.telegram_chat_id)
                  host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
                  game_url = "#{host}/games/#{game.id}"
                  Telegram::Api.send_simple(
                    requester.telegram_chat_id,
                    Telegram::I18n.t(
                      :prebook_requester_all_rejected,
                      locale: requester_locale,
                      game_id: game.id,
                      dates: dates_text,
                      url: game_url
                    )
                  ) rescue nil
                end

                nil

              else
                nil
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::Manage::PrebookApproveFlow] #{e.class} #{e.message}"
              nil
            end

            private

            def update_notification_message(poller, chat_id, message_id, processed_id, action)
              return unless message_id && chat_id

              # Try to get current message to rebuild buttons (remove processed ones)
              # Simplest approach: edit the message to mark the action on the processed button row
              begin
                # Get current message markup
                result = poller.send_api("editMessageReplyMarkup", {
                  chat_id: chat_id,
                  message_id: message_id,
                  reply_markup: { inline_keyboard: [] }
                })
              rescue => e
                Rails.logger.error "[PrebookApproveFlow] editMessageReplyMarkup failed: #{e.class} #{e.message}"
              end
            end
          end
        end
      end
    end
  end
end
