module Telegram
  module Flows
    module Games
      module PrebookFlow
        class << self
          def handle_callback(callback)
            data = (callback["data"] || "").to_s
            cb_id = callback["id"]
            from = callback["from"] || {}
            chat_id = (callback.dig("message","chat","id") || from["id"]).to_s
            message_id = callback.dig("message","message_id")
            poller = Telegram::Poller.new

            Rails.logger.debug "[Telegram::Flows::Games::PrebookFlow] enter handle_callback data=#{data.inspect} chat_id=#{chat_id} cb_id=#{cb_id} msg_id=#{message_id}"

            case data
            when /\Agame:prebook:(\d+)\z/
              game = Game.find_by(id: $1.to_i)
              user = User.find_by(telegram_chat_id: chat_id.to_s)
              unless game && user
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Game or user not found", show_alert: false }) rescue nil
                return
              end

              unless game.prebooking_enabled? && game.recurring?
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Prebooking is not available for this game", show_alert: false }) rescue nil
                return
              end

              game.ensure_prebookings_for_next_weeks

              dates = available_prebook_dates(game)
              if dates.empty?
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Нет доступных дат для предварительной записи", show_alert: false }) rescue nil
                return
              end

              cache_key = "telegram:prebook:#{chat_id}:#{game.id}"
              state = cached_prebook_state(cache_key)
              state[:dates] = dates.map { |d| normalized_prebook_date(d) } # фиксируем порядок для idx
              write_prebook_state(cache_key, state)

              user_booked = user_booked_keys(game, user, dates)
              pending = user_pending_keys(game, user, dates)
              keyboard = build_keyboard(game.id, state[:dates], state, user_booked, user_pending: pending)

              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
              if message_id
                poller.send_api("editMessageText", {
                  chat_id: chat_id,
                  message_id: message_id,
                  text: "Select dates (click to mark):",
                  reply_markup: { inline_keyboard: keyboard }
                }) rescue nil
              else
                poller.send_api("sendMessage", {
                  chat_id: chat_id,
                  text: "Select dates (click to mark):",
                  reply_markup: { inline_keyboard: keyboard }
                }) rescue nil
              end
              return

            when /\Aprebook:toggle:(\d+):(\d+)\z/
              game_id = $1.to_i
              idx = $2.to_i

              game = Game.find_by(id: game_id)
              user = User.find_by(telegram_chat_id: chat_id.to_s)
              unless game && user
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Game or user not found", show_alert: false }) rescue nil
                return
              end

              unless game.prebooking_enabled? && game.recurring?
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Prebooking is not available for this game", show_alert: false }) rescue nil
                return
              end

              game.ensure_prebookings_for_next_weeks

              cache_key = "telegram:prebook:#{chat_id}:#{game.id}"
              state = cached_prebook_state(cache_key)

              # если dates не было в кеше (старый формат/сброс кеша) — пересоберём
              date_keys = Array(state[:dates])
              if date_keys.empty?
                dates = available_prebook_dates(game)
                date_keys = dates.map { |d| normalized_prebook_date(d) }
                state[:dates] = date_keys
              end

              key = date_keys[idx]
              unless key
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Дата устарела, откройте пребукинг заново", show_alert: false }) rescue nil
                return
              end

              parsed_date =
                begin
                  Date.iso8601(key)
                rescue ArgumentError
                  (Date.parse(key) rescue nil)
                end

              unless parsed_date
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Некорректная дата, откройте пребукинг заново", show_alert: false }) rescue nil
                return
              end

              # определяем, было ли уже забронировано пользователем на эту дату
              # (по факту в БД, а не по кешу)
              booked_now = game.prebookings.where(user_id: user.id).where("DATE(date) = ?", parsed_date).exists?

              if booked_now
                # toggle cancel
                if state[:cancel].include?(key)
                  state[:cancel] = state[:cancel] - [key]
                else
                  state[:cancel] = (state[:cancel] + [key]).uniq
                  state[:book] = state[:book] - [key]
                end
              else
                # toggle book
                if state[:book].include?(key)
                  state[:book] = state[:book] - [key]
                else
                  state[:book] = (state[:book] + [key]).uniq
                  state[:cancel] = state[:cancel] - [key]
                end
              end

              write_prebook_state(cache_key, state)

              # rebuild keyboard
              dates = date_keys.map { |s| (Date.parse(s) rescue nil) }.compact
              user_booked = user_booked_keys(game, user, dates)
              pending = user_pending_keys(game, user, dates)
              keyboard = build_keyboard(game.id, date_keys, state, user_booked, user_pending: pending)

              message_id = callback.dig("message","message_id")
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
              poller.send_api("editMessageText", {
                chat_id: chat_id,
                message_id: message_id,
                text: "Select dates (click to mark):",
                reply_markup: { inline_keyboard: keyboard }
              }) rescue nil
              return

            when /\Aprebook:confirm:(\d+)\z/
              game_id = $1.to_i
              game = Game.find_by(id: game_id)
              user = User.find_by(telegram_chat_id: chat_id.to_s)
              unless game && user
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Game or user not found", show_alert: false }) rescue nil
                return
              end

              unless game.prebooking_enabled? && game.recurring?
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Prebooking is not available for this game", show_alert: false }) rescue nil
                return
              end

              cache_key = "telegram:prebook:#{chat_id}:#{game.id}"
              state = cached_prebook_state(cache_key)

              cancel_dates = state[:cancel].map { |s| (Date.parse(s) rescue nil) }.compact.uniq
              book_dates   = state[:book].map   { |s| (Date.parse(s) rescue nil) }.compact.uniq

              cancelled = 0
              cancel_failed = []

              direct_book = user.admin? || user.id == game.user_id

              cancel_dates.each do |d|
                pb = game.prebookings.where(user_id: user.id).where("DATE(date) = ?", d).first
                if pb
                  pb.update!(user_id: nil, status: "approved", approved_at: nil)
                  cancelled += 1
                else
                  cancel_failed << d.to_s
                end
              end

              user_booked_dates = game.prebookings.where(user: user).pluck(:date).map { |x| x.to_date }
              to_book = book_dates - user_booked_dates

              Rails.cache.delete(cache_key)

              booked = 0
              pending_count = 0
              failed = []
              new_pending_prebookings = []

              to_book.each do |d|
                next if PrebookingCancellation.exists?(game_id: game.id, date: d)
                slot = game.prebookings.where(user_id: nil).where("DATE(date) = ?", d).first
                if slot
                  if direct_book
                    slot.update!(user: user, status: "approved", approved_at: Time.current)
                    booked += 1
                  else
                    slot.update!(user: user, status: "pending")
                    pending_count += 1
                    new_pending_prebookings << slot
                  end
                else
                  failed << d.to_s
                end
              end

              # Send notification to owner only if there are new pending bookings
              if new_pending_prebookings.any?
                notify_owner_about_prebookings(game, user, new_pending_prebookings, poller)
              end

              Rails.logger.info "[Telegram::Flows::Games::PrebookFlow] result booked=#{booked} pending=#{pending_count} cancelled=#{cancelled} failed=#{failed.inspect} cancel_failed=#{cancel_failed.inspect}"

              result_parts = []
              result_parts << "Booked: #{booked}" if booked > 0
              result_parts << "Pending approval: #{pending_count}" if pending_count > 0
              result_parts << "Cancelled: #{cancelled}" if cancelled > 0
              result_parts << "Failed: #{failed.join(', ')}" if failed.any?
              result_text = result_parts.any? ? result_parts.join(", ") : "No changes"

              poller.send_api("answerCallbackQuery", {
                callback_query_id: cb_id,
                text: result_text,
                show_alert: false
              }) rescue nil

              Telegram::Handlers::GamesHandler.show_game(chat_id, game.id, 1, message_id: message_id) rescue (Rails.logger.error "[Telegram::Flows::Games::PrebookFlow] show_game refresh failed: #{$!.class} #{$!.message}")
              return

            else
              Rails.logger.warn "[Telegram::Flows::Games::PrebookFlow] unknown prebook action data=#{data}"
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Unknown prebook action", show_alert: false }) rescue nil
              return
            end
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::PrebookFlow] callback error: #{e.class} #{e.message}\n#{e.backtrace.first(6).join("\n")}"
          end

          # ---- helpers ----

          def available_prebook_dates(game)
            dates = Array(game.prebooking_candidate_dates(3)).map(&:to_date)
            required = (game.prebooking_required_players rescue nil)
            Rails.logger.debug "[Telegram::Flows::Games::PrebookFlow] candidate_dates_before_filter=#{dates.inspect} required=#{required}"

            dates.select do |d|
              !PrebookingCancellation.where(game_id: game.id).where("DATE(date) = ?", d).exists? &&
                game.prebookings.where("DATE(date) = ?", d).exists?
            end.sort
          end

          def user_booked_keys(game, user, dates)
            return Set.new unless user
            keys = game.prebookings.where(user_id: user.id).where("DATE(date) IN (?)", dates).pluck(:date).map { |x| normalized_prebook_date(x) }
            keys.to_set
          end

          def user_pending_keys(game, user, dates)
            return Set.new unless user
            keys = game.prebookings.where(user_id: user.id, status: "pending").where("DATE(date) IN (?)", dates).pluck(:date).map { |x| normalized_prebook_date(x) }
            keys.to_set
          end

          def build_keyboard(game_id, date_keys, state, user_booked, page: 1, user_pending: Set.new)
            rows = date_keys.each_with_index.map do |key, i|
              if user_booked.include?(key)
                if user_pending.include?(key)
                  # Pending booking — show hourglass
                  checked = state[:cancel].include?(key) ? "☐" : "⏳"
                else
                  checked = state[:cancel].include?(key) ? "☐" : "☑"
                end
                [{ text: "#{checked} #{key}", callback_data: "prebook:toggle:#{game_id}:#{i}" }]
              else
                checked = state[:book].include?(key) ? "☑" : "☐"
                [{ text: "#{checked} #{key}", callback_data: "prebook:toggle:#{game_id}:#{i}" }]
              end
            end

            rows << [{ text: "Confirm", callback_data: "prebook:confirm:#{game_id}" }]
            rows << [{ text: "Back to game", callback_data: "game:show:#{game_id}:#{page}" }]
            rows
          end

          def notify_owner_about_prebookings(game, user, prebookings, poller)
            owner_chat_id = game.user&.telegram_chat_id
            return unless owner_chat_id.present?

            requester = if user.respond_to?(:telegram_username) && user.telegram_username.present?
                          "@#{user.telegram_username}"
                        elsif user.respond_to?(:username) && user.username.present?
                          "@#{user.username}"
                        else
                          user.name.presence || user.email.presence || "User"
                        end

            dates_text = prebookings.map { |pb| pb.date.strftime("%Y-%m-%d") }.sort.join(", ")
            host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
            game_url = "#{host}/games/#{game.id}"
            text = "Prebooking request for Game ##{game.id} from #{requester}\nDates: #{dates_text}\n\n#{game_url}"

            buttons = [
              [
                { text: "Approve All", callback_data: "game:approve_all_prebookings:#{game.id}:#{user.id}" },
                { text: "Reject All",  callback_data: "game:reject_all_prebookings:#{game.id}:#{user.id}" }
              ]
            ]

            poller.send_api("sendMessage", {
              chat_id: owner_chat_id,
              text: text,
              reply_markup: { inline_keyboard: buttons }
            }) rescue nil
          end

          # ---- helpers for telegram prebook state ----

          def cached_prebook_state(cache_key)
            raw = Rails.cache.read(cache_key)
            if raw.is_a?(Array)
              return { book: raw.map { |d| normalized_prebook_date(d) }.uniq, cancel: [], dates: [] }
            end
            book = Array(raw.is_a?(Hash) ? (raw[:book] || raw["book"]) : nil).map { |d| normalized_prebook_date(d) }.uniq
            cancel = Array(raw.is_a?(Hash) ? (raw[:cancel] || raw["cancel"]) : nil).map { |d| normalized_prebook_date(d) }.uniq
            dates = Array(raw.is_a?(Hash) ? (raw[:dates] || raw["dates"]) : nil).map { |d| normalized_prebook_date(d) }.uniq
            { book: book, cancel: cancel, dates: dates }
          end

          def write_prebook_state(cache_key, state)
            Rails.logger.debug "[Telegram::Flows::Games::PrebookFlow] write_prebook_state cache_key=#{cache_key} state=#{state.inspect}"
            Rails.cache.write(
              cache_key,
              { book: Array(state[:book]).uniq, cancel: Array(state[:cancel]).uniq, dates: Array(state[:dates]).uniq },
              expires_in: 30.minutes
            )
          end

          def normalized_prebook_date(value)
            case value
            when Date, Time, ActiveSupport::TimeWithZone
              value.to_date.iso8601
            else
              Date.parse(value.to_s).iso8601 rescue value.to_s
            end
          end
        end
      end
    end
  end
end
