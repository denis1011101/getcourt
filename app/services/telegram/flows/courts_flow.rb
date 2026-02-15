module Telegram
  module Flows
    class CourtsFlow
      class << self
        # Entry for callback_query handling related to courts
        def handle_callback(callback)
          cb = Telegram::Helpers::CallbackData.parse(callback)
          poller = Telegram::Poller.new

          case cb.data
          when /\Acourt:games:(\d+):(\d+)\z/
            court_id = $1.to_i
            page = $2.to_i
            Telegram::Handlers::CourtsHandler.list_games(cb.chat_id, court_id, page, message_id: cb.message_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            nil
          when /\Amenu:courts(?:\:page:(\d+))?\z/
            page = ($1 || 1).to_i
            Telegram::Handlers::CourtsHandler.list_page(cb.chat_id, page)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Courts", show_alert: false }) rescue nil
            nil
          when /\Acourt:show:(\d+)(?::(\d+))?\z/
            court_id = $1.to_i
            page = ($2 || 1).to_i
            Telegram::Handlers::CourtsHandler.show_court(cb.chat_id, court_id, page, message_id: cb.message_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            nil
          when /\Acreate_game_from_court:(\d+)\z/
            start_create_game_from_court(cb.chat_id, $1.to_i, cb_id: cb.cb_id, message_id: cb.message_id)
            nil
          when /\Acourt:edit:(\d+)\z/
            start_edit_court(cb.chat_id, $1.to_i, cb_id: cb.cb_id)
            nil
          when /\Acourt:delete:(\d+)(?::(\d+))?\z/
            court_id = $1.to_i
            page = ($2 || 1).to_i
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
            delete_court(cb.chat_id, court_id, page)
            nil
          when /\Acourt:create\z/
            start_create_court(cb.chat_id, cb_id: cb.cb_id)
            nil
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: "Unknown courts action", show_alert: false }) rescue nil
            nil
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::CourtsFlow] callback error: #{e.class} #{e.message}"
        end

        # Initiate create-game flow prefilled with court_id via interactive buttons
        def start_create_game_from_court(chat_id, court_id, cb_id: nil, message_id: nil)
          poller = Telegram::Poller.new
          Rails.logger.debug "[Telegram::Flows::CourtsFlow] start_create_game_from_court called message_id=#{message_id.inspect} chat_id=#{chat_id} cb_id=#{cb_id.inspect}"
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No linked account. Send /start first.", show_alert: false }) rescue nil
            return
          end

          poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Create game — use buttons to set fields", show_alert: false }) rescue nil

          # create draft game so we can reuse edit flows/buttons (will be deleted on cancel if not saved)
          begin
            # provide required :date to satisfy model validation; use a safe future date
            draft = Game.create(user_id: user.id, court_id: court_id, players_count: 4, date: (Time.zone.today + 7))
          rescue => e
            Rails.logger.error "[Telegram::Flows::CourtsFlow] draft create exception: #{e.class} #{e.message}"
            poller.send_api("sendMessage", { chat_id: chat_id, text: "Failed to create draft game: #{e.message}" }) rescue nil
            return
          end
          unless draft && draft.persisted?
            errs = draft ? draft.errors.full_messages.join("; ") : "unknown error"
            Rails.logger.error "[Telegram::Flows::CourtsFlow] draft not persisted: #{errs}"
            poller.send_api("sendMessage", { chat_id: chat_id, text: "Failed to create draft game: #{errs}" }) rescue nil
            return
          end
          gid = draft.id

          # pass original message_id so cancel can restore the court card
          buttons = Telegram::Flows::Games::EditPrompter.build_buttons(:create, gid, message_id)
          text = Telegram::Flows::Games::EditPrompter.prompt_text(:create, gid)
          if message_id && message_id.to_s.strip != ""
            Rails.logger.debug "[Telegram::Flows::CourtsFlow] edit attempt message_id=#{message_id.inspect} chat_id=#{chat_id}"
            resp = Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
            Rails.logger.debug "[Telegram::Flows::CourtsFlow] edit_message_with_buttons resp=#{resp.inspect}"
            # fallback to sending new message when edit fails
            if resp.nil? || (resp.is_a?(Hash) && resp["ok"] == false)
              Rails.logger.warn "[Telegram::Flows::CourtsFlow] edit failed, sending new message"
              poller.send_api("sendMessage", {
                chat_id: chat_id,
                text: text,
                reply_markup: { inline_keyboard: buttons }
              }) rescue nil
            end
          else
            poller.send_api("sendMessage", {
              chat_id: chat_id,
              text: text,
              reply_markup: { inline_keyboard: buttons }
            }) rescue nil
          end
        end

        # Initiate edit-court flow (permission check)
        def start_edit_court(chat_id, court_id, cb_id: nil)
          poller = Telegram::Poller.new
          court = Court.find_by(id: court_id)
          unless court
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Court not found", show_alert: false }) rescue nil
            return
          end
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user && (user.admin? || user.id == court.user_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No permission to edit", show_alert: true }) rescue nil
            return
          end

          poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Edit court — reply with updated info", show_alert: false }) rescue nil
          poller.send_api("sendMessage", {
            chat_id: chat_id,
            text: "COURT_EDIT_PROMPT #{court_id}\nReply with: Name; lat,lon; contact_type:contact_value",
            reply_markup: { force_reply: true, selective: true }
          })
        end

        # Start create court flow (from menu) — delegates to new step-by-step flow
        def start_create_court(chat_id, cb_id: nil)
          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Flows::CourtCreateFlow.start(chat_id)
        end

        # Delete a court (permission check)
        def delete_court(chat_id, court_id, page = 1)
          poller = Telegram::Poller.new
          court = Court.find_by(id: court_id)
          unless court
            poller.send_api("sendMessage", { chat_id: chat_id, text: "Court not found." }) rescue nil
            return
          end
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user && (user.admin? || user.id == court.user_id)
            poller.send_api("sendMessage", { chat_id: chat_id, text: "No permission to delete this court." }) rescue nil
            return
          end

          court.destroy
          poller.send_api("sendMessage", { chat_id: chat_id, text: "Court deleted." }) rescue nil
          Telegram::Handlers::CourtsHandler.list_page(chat_id, page)
        end
      end
    end
  end
end
