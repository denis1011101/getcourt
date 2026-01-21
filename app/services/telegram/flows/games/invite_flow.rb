module Telegram
  module Flows
    module Games
      module InviteFlow
        PROMPT_PREFIX = "INVITE_PROMPT game:".freeze

        class << self
          # callback_query entry
          def handle_callback(callback)
            data = (callback["data"] || "").to_s
            return false unless data.start_with?("game:invite:") || data.start_with?("game:invite_decline:")

            cb_id = callback["id"]
            from = callback["from"] || {}
            chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
            poller = Telegram::Poller.new

            case data
            when /\Agame:invite:(\d+)\z/
              game_id = $1.to_i
              game = Game.find_by(id: game_id)
              inviter = User.find_by(telegram_chat_id: chat_id)

              unless game && inviter && (inviter.admin? || game.user_id == inviter.id)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Only the game owner can invite", show_alert: false }) rescue nil
                return true
              end

              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Reply with usernames to invite", show_alert: false }) rescue nil
              poller.send_api("sendMessage", {
                chat_id: chat_id,
                text: "#{PROMPT_PREFIX}#{game_id}\nReply to this message with usernames to invite (e.g. @alice @bob).",
                reply_markup: { force_reply: true, selective: true }
              }) rescue nil
              return true

            when /\Agame:invite_decline:(\d+)\z/
              game_id = $1.to_i
              game = Game.find_by(id: game_id)
              decliner = User.find_by(telegram_chat_id: chat_id)

              poller.send_api(
                "answerCallbackQuery",
                { callback_query_id: cb_id, text: "Invite declined", show_alert: false }
              ) rescue nil

              # NEW: update the invite message text + remove buttons
              msg = callback["message"] || {}
              msg_id = msg["message_id"]
              if msg_id.present?
                poller.send_api("editMessageText", {
                  chat_id: chat_id,
                  message_id: msg_id,
                  text: "You declined the invitation to the game ##{game_id}.",
                  reply_markup: { inline_keyboard: [] }
                }) rescue nil
              end

              if game&.user&.telegram_chat_id.present?
                name = decliner&.name.presence || decliner&.username.presence || decliner&.telegram_username.presence || "User"
                poller.send_api(
                  "sendMessage",
                  { chat_id: game.user.telegram_chat_id.to_s, text: "#{name} declined invite to game ##{game_id}." }
                ) rescue nil
              end

              return true
            end

            false
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::InviteFlow] callback error: #{e.class} #{e.message}"
            false
          end

          # message entry (reply to INVITE_PROMPT)
          def handle_message(message)
            rt = message.dig("reply_to_message", "text").to_s
            return false unless rt.start_with?(PROMPT_PREFIX)

            chat_id = message.dig("chat", "id").to_s
            poller = Telegram::Poller.new

            game_id = rt.sub(PROMPT_PREFIX, "").to_i
            game = Game.find_by(id: game_id)
            inviter = User.find_by(telegram_chat_id: chat_id)

            unless game && inviter && (inviter.admin? || game.user_id == inviter.id)
              poller.send_api("sendMessage", { chat_id: chat_id, text: "Only the game owner can send invites." }) rescue nil
              return true
            end

            text = message["text"].to_s
            handles = text.scan(/@[\w\d_]+/i).map { |h| h.delete_prefix("@").downcase }.uniq
            if handles.empty?
              poller.send_api("sendMessage", { chat_id: chat_id, text: "No usernames found. Example: @alice @bob" }) rescue nil
              return true
            end

            resolved = resolve_users_by_handles(handles)
            not_found = []
            skipped_self = []

            resolved.each do |handle, user|
              if user.nil?
                not_found << "@#{handle}"
                next
              end

              if user.id == inviter.id
                skipped_self << "@#{handle}"
                next
              end

              next unless user.telegram_chat_id.present?

              label =
                if Telegram::Handlers::GamesHandler.respond_to?(:game_label)
                  Telegram::Handlers::GamesHandler.game_label(game)
                else
                  "Game ##{game.id}"
                end

              poller.send_api("sendMessage", {
                chat_id: user.telegram_chat_id.to_s,
                text: "You are invited to join:\n#{label}",
                reply_markup: {
                  inline_keyboard: [[
                    { text: "Join ##{game.id}", callback_data: "game:join:#{game.id}" },
                    { text: "Decline ##{game.id}", callback_data: "game:invite_decline:#{game.id}" }
                  ]]
                }
              }) rescue nil
            end

            summary =
              if not_found.empty? && skipped_self.empty?
                "Invitations sent."
              else
                parts = []
                parts << "Not found: #{not_found.join(', ')}" if not_found.any?
                parts << "Skipped self: #{skipped_self.join(', ')}" if skipped_self.any?
                "Invitations processed. #{parts.join('. ')}"
              end

            poller.send_api("sendMessage", { chat_id: chat_id, text: summary }) rescue nil
            true
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::InviteFlow] message error: #{e.class} #{e.message}"
            false
          end

          private

          def resolve_users_by_handles(handles)
            map = {}

            # allow numeric chat_id in input too
            numeric = handles.select { |h| h.match?(/\A\d+\z/) }

            by_chat_id = {}
            if numeric.any?
              User.where(telegram_chat_id: numeric).find_each do |u|
                by_chat_id[u.telegram_chat_id.to_s] = u
              end
            end

            # username columns may differ; check safely
            cols = User.column_names
            uname_cols = []
            uname_cols << "telegram_username" if cols.include?("telegram_username")
            uname_cols << "username" if cols.include?("username")

            by_username = {}
            if uname_cols.any?
              # build OR query: lower(col) IN (handles)
              conds = uname_cols.map { |c| "LOWER(#{c}) IN (:hs)" }.join(" OR ")
              User.where(conds, hs: handles).find_each do |u|
                uname_cols.each do |c|
                  v = u.public_send(c).to_s.downcase
                  by_username[v] = u if v.present?
                end
              end
            end

            handles.each do |h|
              map[h] = by_chat_id[h] || by_username[h]
            end
            map
          end
        end
      end
    end
  end
end
