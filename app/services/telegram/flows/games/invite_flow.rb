module Telegram
  module Flows
    module Games
      module InviteFlow
        PROMPT_PREFIX = "INVITE_PROMPT game:".freeze

        class << self
          # callback_query entry
          def handle_callback(callback)
            data = (callback["data"] || "").to_s
            return false unless data.start_with?("game:invite_decline:")

            cb_id = callback["id"]
            from = callback["from"] || {}
            chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
            message_id = callback.dig("message", "message_id")
            poller = Telegram::Poller.new

            case data
            # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
            # бот оставлен только для приглашений и карточки игры.
            # Раскомментировать, если решим вернуть функциональность в бот.
            # when /\Agame:invite:(\d+)\z/
            #   game_id = $1.to_i
            #   game = Game.find_by(id: game_id)
            #   inviter = User.find_by(telegram_chat_id: chat_id)
            #   unless game && inviter && (inviter.admin? || game.user_id == inviter.id)
            #     poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Only the game owner can invite", show_alert: false }) rescue nil
            #     return true
            #   end
            #   Rails.cache.write(invite_cache_key(chat_id), game_id, expires_in: 10.minutes)
            #   poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Send usernames to invite", show_alert: false }) rescue nil
            #   if message_id
            #     poller.send_api("editMessageText", {
            #       chat_id: chat_id,
            #       message_id: message_id,
            #       text: "Send usernames to invite (e.g. @alice @bob).\nSend /cancel to abort.",
            #       reply_markup: { inline_keyboard: [ [ { text: "Cancel", callback_data: "game:invite_cancel:#{game_id}" } ] ] }
            #     }) rescue nil
            #   else
            #     poller.send_api("sendMessage", {
            #       chat_id: chat_id,
            #       text: "Send usernames to invite (e.g. @alice @bob).\nSend /cancel to abort.",
            #       reply_markup: { inline_keyboard: [ [ { text: "Cancel", callback_data: "game:invite_cancel:#{game_id}" } ] ] }
            #     }) rescue nil
            #   end
            #   return true
            # when /\Agame:invite_cancel:(\d+)\z/
            #   game_id = $1.to_i
            #   Rails.cache.delete(invite_cache_key(chat_id))
            #   poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Invite cancelled", show_alert: false }) rescue nil
            #   Telegram::Handlers::GamesHandler.show_game(chat_id, game_id, 1, message_id: message_id) rescue nil
            #   return true

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

          # message entry (reply to INVITE_PROMPT) OR pending invite state
          def handle_message(message)
            chat_id = message.dig("chat", "id").to_s
            text = message["text"].to_s.strip
            poller = Telegram::Poller.new

            # allow explicit cancel
            if text.casecmp("/cancel").zero?
              if Rails.cache.delete(invite_cache_key(chat_id))
                poller.send_api("sendMessage", { chat_id: chat_id, text: "Invite cancelled." }) rescue nil
                return true
              end
              return false
            end

            # Backward compatibility: old flow via reply_to_message prefix
            rt = message.dig("reply_to_message", "text").to_s
            game_id =
              if rt.start_with?(PROMPT_PREFIX)
                rt.sub(PROMPT_PREFIX, "").to_i
              else
                Rails.cache.read(invite_cache_key(chat_id)).to_i
              end

            return false if game_id <= 0

            game = Game.find_by(id: game_id)
            inviter = User.find_by(telegram_chat_id: chat_id)

            unless game && inviter && (inviter.admin? || game.user_id == inviter.id)
              Rails.cache.delete(invite_cache_key(chat_id))
              poller.send_api("sendMessage", { chat_id: chat_id, text: "Only the game owner can send invites." }) rescue nil
              return true
            end

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

              target_locale = Telegram::Helpers::UserLookup.locale_for(user.telegram_chat_id)
              label =
                if Telegram::Handlers::GamesHandler.respond_to?(:game_label)
                  # IMPORTANT: show inviter nick (not game owner) in the label
                  Telegram::Handlers::GamesHandler.game_label(game, owner: inviter, locale: target_locale)
                else
                  "Game ##{game.id}"
                end

              host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
              game_url = "#{host}/games/#{game.id}"

              poller.send_api("sendMessage", {
                chat_id: user.telegram_chat_id.to_s,
                text: [
                  "You are invited to join:",
                  label
                ].compact.join("\n") + "\n\n#{game_url}",
                reply_markup: {
                  inline_keyboard: [ [
                    { text: "Join ##{game.id}", callback_data: "game:join_invited:#{game.id}" },
                    { text: "Decline ##{game.id}", callback_data: "game:invite_decline:#{game.id}" }
                  ] ]
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

            Rails.cache.delete(invite_cache_key(chat_id))
            poller.send_api("sendMessage", { chat_id: chat_id, text: summary }) rescue nil
            true
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::InviteFlow] message error: #{e.class} #{e.message}"
            false
          end

          private

          def invite_cache_key(chat_id)
            "telegram:invite_flow:pending:#{chat_id}"
          end

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
