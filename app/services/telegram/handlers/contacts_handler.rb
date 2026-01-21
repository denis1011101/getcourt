module Telegram
  module Handlers
    class ContactsFlow
      class << self
        # Entry for callback_query handling related to courts
        def handle_callback(callback)
          data = (callback["data"] || "").to_s
          cb_id = callback["id"]
          from = callback["from"] || {}
          chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
          poller = Telegram::Poller.new

          case data
          when /\Amenu:courts(?:\:page:(\d+))?\z/
            page = ($1 || 1).to_i
            Telegram::Handlers::CourtsHandler.list_page(chat_id, page)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Courts", show_alert: false }) rescue nil
            nil
          when /\Acourt:show:(\d+)(?::(\d+))?\z/
            court_id = $1.to_i
            page = ($2 || 1).to_i
            Telegram::Handlers::CourtsHandler.show_court(chat_id, court_id, page, message_id: msg_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            nil
          when /\Acreate_game_from_court:(\d+)\z/
            start_create_game_from_court(chat_id, $1.to_i, cb_id: cb_id)
            nil
          when /\Acourt:edit:(\d+)\z/
            start_edit_court(chat_id, $1.to_i, cb_id: cb_id)
            nil
          when /\Acourt:create\z/
            start_create_court(chat_id, cb_id: cb_id)
            nil
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Unknown courts action", show_alert: false }) rescue nil
            nil
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::CourtsFlow] callback error: #{e.class} #{e.message}"
        end

        # Initiate create-game flow prefilled with court_id via ForceReply
        def start_create_game_from_court(chat_id, court_id, cb_id: nil)
          poller = Telegram::Poller.new
          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          if user
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Create game — reply with details", show_alert: false }) rescue nil
            poller.send_api("sendMessage", {
              chat_id: chat_id,
              text: "GAME_PROMPT_FROM_COURT #{court_id}\nReply with: date(YYYY-MM-DD) time(HH:MM) players_count sport\nExample:\n2025-12-10 19:00 4 tennis",
              reply_markup: { force_reply: true, selective: true }
            })
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No linked account. Send /start first.", show_alert: false }) rescue nil
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
          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
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

        # Start create court flow (from menu)
        def start_create_court(chat_id, cb_id: nil)
          poller = Telegram::Poller.new
          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
          if user
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Create court — reply with details", show_alert: false }) rescue nil
            poller.send_api("sendMessage", {
              chat_id: chat_id,
              text: "COURT_PROMPT\nReply with court info in one line or multiple lines:\nName; lat,lon; contact_type:contact_value\nExample:\nCentral Court; 55.7558,37.6173; telegram:ivan123",
              reply_markup: { force_reply: true, selective: true }
            })
          else
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No linked account. Send /start first.", show_alert: false }) rescue nil
          end
        end
      end
    end
  end
end
