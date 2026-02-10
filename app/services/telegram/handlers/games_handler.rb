module Telegram
  module Handlers
    class GamesHandler
      PER_PAGE = 5

      class << self
        extend Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          buttons = [
            [ { text: "All games",   callback_data: "menu:games:page:1" } ],
            [ { text: "Create game", callback_data: "game:create" } ],
            [ { text: "Main menu",  callback_data: "menu:main" } ]
          ]
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "Games menu:", buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, "Games menu:", buttons)
          end
        end

        def owner_display(user)
          return nil unless user

          # prefer telegram nick
          if user.respond_to?(:telegram_username) && user.telegram_username.to_s.strip.present?
            "@#{user.telegram_username.to_s.strip.delete_prefix('@')}"
          elsif user.respond_to?(:username) && user.username.to_s.strip.present?
            "@#{user.username.to_s.strip.delete_prefix('@')}"
          else
            user.name.to_s.strip.presence || "User"
          end
        end

        # Return label used in games lists (shared formatter used everywhere)
        # owner: override whose nick is shown (default: game.user)
        def game_label(g, owner: nil)
          date = game_datetime_for_ui(g)

          # safe title extraction: prefer title, then sport
          title =
            if g.respond_to?(:has_attribute?) && g.has_attribute?(:title)
              g.title.to_s.strip.presence
            elsif g.respond_to?(:sport)
              g.sport.to_s.strip.presence
            else
              nil
            end

          required = (g.respond_to?(:players_count) && g.players_count.to_i > 0) ? g.players_count.to_i : 4
          approved_count =
            if g.participations.loaded?
              g.participations.select { |p| p.respond_to?(:approved?) ? p.approved? : (p.status == 'approved') }.size
            else
              g.participations.respond_to?(:approved) ? g.participations.approved.count : g.participations.count
            end
          taken = approved_count
          spots_left = required - taken
          spots_left = 0 if spots_left.negative?
          spots_text = "#{spots_left} spot#{'s' if spots_left != 1} left"

          # Always add game ID to title/sport
          title_with_id = "#{title || (g.respond_to?(:title) && g.title.to_s.presence) || 'Game'} ##{g.id}"
          parts = [ title_with_id, date, spots_text ].compact
          parts.join(" — ")
        end

        # Send a page with list of games
        def list_page(chat_id, page = 1, message_id: nil)
          page = page.to_i < 1 ? 1 : page.to_i

          # Город текущего пользователя — игры в его городе будут показаны первыми
          current_user = User.find_by(telegram_chat_id: chat_id)
          user_city = current_user&.city_name.to_s.strip.downcase.presence

          # 1. Загружаем только повторяющиеся ИЛИ те, что будут в будущем (или сегодня).
          # Это сразу убирает из Ruby-обработки весь старый мусор.
          all_games = Game.includes(:user, :court, :participations, :prebooking_cancellations)
                          .where("recurring = ? OR date >= ?", true, Date.current)
                          .to_a

          # 2. Предварительно вычисляем ключи сортировки (Дата и Время как число),
          # чтобы не делать тяжелых вычислений внутри sort_by.
          today = Date.current
          # Получаем текущее время как число HHMM (например, 2130 для 21:30)
          now = Time.zone.now
          now_hhmm = now.hour * 100 + now.min

          # Преобразуем массив игр в массив хешей с готовыми ключами
          mapped_games = all_games.map do |g|
            # display_date_for_show используем из модели (с оптимизацией cancelled_on?)
            d = g.display_date_for_show
            # Если даты нет (всё отменено), кидаем в конец времен (9999 год)
            sort_date = d || Date.new(9999, 12, 31)

            # Вычисляем время как число (integer), чтобы сравнение было мгновенным
            # g.next_time может быть Time или String
            t_obj = g.respond_to?(:next_time) ? g.next_time : g.time
            hhmm = 0
            if t_obj.respond_to?(:strftime)
              hhmm = t_obj.strftime("%H%M").to_i
            elsif t_obj.to_s.include?(":")
              parts = t_obj.to_s.split(":")
              # часы * 100 + минуты
              hhmm = parts[0].to_i * 100 + parts[1].to_i
            end

            # Определяем, игра в будущем или прошлом (для разделения списков)
            is_future = if sort_date > today
                          true
                        elsif sort_date < today
                          false
                        else
                          # Если сегодня — сравниваем время
                          hhmm >= now_hhmm
                        end

            # Совпадает ли город корта с городом пользователя (0 = свой город, 1 = другой)
            same_city = if user_city && g.court&.city_name.to_s.strip.downcase == user_city
                          0
                        else
                          1
                        end

            { game: g, date: sort_date, time: hhmm, is_future: is_future, city_rank: same_city }
          end

          # 3. Разделяем списки (Upcoming vs Past), используя булеан is_future
          future_items, past_items = mapped_games.partition { |item| item[:is_future] }

          # 4. Сортируем: сначала свой город, потом по дате и времени.
          sorter = ->(item) { [item[:city_rank], item[:date], item[:time]] }

          sorted_future = future_items.sort_by(&sorter)
          sorted_past   = past_items.sort_by(&sorter)

          # 5. Собираем обратно объекты Game и применяем пагинацию
          sorted_games = (sorted_future + sorted_past).map { |item| item[:game] }

          total = sorted_games.size
          pages = (total.to_f / PER_PAGE).ceil
          offset = (page - 1) * PER_PAGE
          games = sorted_games.slice(offset, PER_PAGE) || []

          header = "Games — page #{page}/#{[ pages, 1 ].max}"

          if games.empty?
            send_or_edit_text(chat_id, "#{header}\n\nNo games on this page.", message_id: message_id)
            return
          end

          buttons = games.map do |g|
            [ { text: game_label(g), callback_data: "game:show:#{g.id}:#{page}" } ]
          end

          nav = []
          nav << [ { text: "‹ Prev", callback_data: "menu:games:page:#{page - 1}" } ] if page > 1
          nav << [ { text: "Next ›", callback_data: "menu:games:page:#{page + 1}" } ] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [ { text: "Main menu", callback_data: "menu:main" } ]

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, header, buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, header, buttons)
          end
        end

        # Show game card with action buttons (join, prebook, edit/delete if owner/admin, back)
        def show_game(chat_id, game_id, page = 1, message_id: nil)
          Rails.logger.debug "[Telegram::Handlers::GamesHandler] show_game chat=#{chat_id} game_id=#{game_id} page=#{page} msg_id=#{message_id}"
          game = Game.find_by(id: game_id)
          return Telegram::Api.send_simple(chat_id, "Game not found.") unless game

          # participants / owner info
          participants_count =
            if game.respond_to?(:participations)
              game.participations.respond_to?(:approved) ? game.participations.approved.size : game.participations.size
            else
              0
            end
          capacity = (game.respond_to?(:players_count) && game.players_count.to_i > 0) ? game.players_count.to_i : "?"
          players_line = "Players: #{participants_count}/#{capacity}"
          owner = User.find_by(id: game.user_id) rescue nil
          owner_line =
            if owner && owner.respond_to?(:telegram_username) && owner.telegram_username.present?
              "Owner: @#{owner.telegram_username}"
            elsif owner && owner.respond_to?(:username) && owner.username.present?
              "Owner: @#{owner.username}"
            elsif owner && owner.respond_to?(:name) && owner.name.present?
              "Owner: #{owner.name}"
            else
              "Owner: #{owner&.telegram_chat_id || '—'}"
            end

          host = ENV.fetch("APP_HOST", "https://getcourt.co")
          game_url = Rails.application.routes.url_helpers.game_url(game, host: host)

          lines = []
          # safe title extraction: prefer title, then sport
          title =
            if game.respond_to?(:has_attribute?) && game.has_attribute?(:title)
              game.title.to_s.strip.presence
            elsif game.respond_to?(:sport)
              game.sport.to_s.strip.presence
            else
              nil
            end

          # always show either the title/sport or fallback to "Game", always with game id on the first line
          title_text = "#{title || 'Game'} ##{game.id}"
          lines << "*#{title_text}*"

          coach = coach_badge_for(game)
          lines << "Coach: #{coach}" if coach.present?

          when_str = game_datetime_for_ui(game)
          lines << "When: #{when_str}" if when_str.present?

          lines << players_line
          lines << ("Court: #{game.court&.name}") if game.respond_to?(:court) && game.court
          lines << owner_line
          text = lines.compact.join("\n")

          buttons = []

          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil

          participation = user ? game.participations.find_by(user_id: user.id) : nil
          direct_join = user && (user.admin? || user.id == game.user_id)
          join_btn =
            if participation && participation.respond_to?(:pending?) && participation.pending?
              { text: "Request sent", callback_data: "game:join_pending:#{game.id}" }
            elsif participation
              { text: "Leave", callback_data: "game:leave:#{game.id}" }
            else
              label = direct_join ? "Join" : "Request to join"
              { text: label, callback_data: "game:join:#{game.id}" }
            end

          row1 = [ join_btn ]

          # показываем пребукинг только когда включён
          if game.prebooking_enabled? && (!game.respond_to?(:recurring?) || game.recurring?)
            row1 << { text: "Prebooking", callback_data: "game:prebook:#{game.id}" }
          end

          buttons << row1

          # статистика: залочена до начала игры (по TZ создателя), после начала — открывает tg_fill
          can_fill_stats = user && (user.admin? || user.id == game.user_id)

          if game.started_for_ui?
            if can_fill_stats
              buttons << [ { text: "Statistics", callback_data: "tg_fill:#{game.id}:#{page}" } ]
            else
              buttons << [ { text: "Statistics", callback_data: "tg_stats_unauthorized:#{game.id}" } ]
            end
          else
            buttons << [ { text: "Statistics (locked)", callback_data: "tg_stats_locked:#{game.id}" } ]
          end

          if user && (user.admin? || user.id == game.user_id)
            buttons << [ { text: "Invite players", callback_data: "game:invite:#{game.id}" } ]
            buttons << [ { text: "Manage players", callback_data: "game:manage:#{game.id}:#{page}" } ]
            buttons << [ { text: "Edit", callback_data: "game:edit:#{game.id}" } ]
            buttons << [ { text: "Delete", callback_data: "game:delete:#{game.id}:#{page}" } ]
          end

          buttons << [ { text: "Open game in browser", url: game_url } ] unless host.to_s.include?("localhost")

          buttons << [ { text: "Back to games", callback_data: "menu:games:page:#{page}" } ]

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons)
          end
        end

        private

        def coach_badge_for(game)
          return nil unless game

          # mirror the same semantics used in [`GamesController#game_badges`](app/controllers/games_controller.rb)
          if game.respond_to?(:with_coach?) && game.with_coach?
            "With coach"
          elsif game.respond_to?(:needs_coach?) && game.needs_coach?
            "Need coach"
          elsif game.respond_to?(:with_coach?) || game.respond_to?(:needs_coach?)
            "No coach"
          else
            nil
          end
        end

        # Uses the same “occurrence” logic as UI: display_date_for_show -> next_date -> date
        # If time is missing, unlock at start of the day.
        def game_start_at_for_ui(g)
          # IMPORTANT: this method relies on Time.zone (caller wraps Time.use_zone)
          d =
            if g.respond_to?(:display_date_for_show)
              g.display_date_for_show
            elsif g.respond_to?(:next_date)
              g.next_date
            elsif g.respond_to?(:date)
              g.date
            end
          return nil unless d.present?

          t =
            if g.respond_to?(:next_time)
              g.next_time
            elsif g.respond_to?(:time)
              g.time
            end

          date =
            if d.respond_to?(:to_date)
              d.to_date
            else
              Date.parse(d.to_s) rescue nil
            end
          return nil unless date

          hh = 0
          mm = 0

          if t.respond_to?(:strftime)
            hh = t.strftime("%H").to_i
            mm = t.strftime("%M").to_i
          else
            s = format_time_hhmm(t)
            if s.present?
              parts = s.split(":")
              hh = parts[0].to_i
              mm = parts[1].to_i
            end
          end

          Time.zone.local(date.year, date.month, date.day, hh, mm, 0)
        end

        # Prefer Game model occurrence logic: display_date_for_show -> next_date -> date.
        # Keep output like "YYYY-MM-DD HH:MM" (as in the list now).
        def game_datetime_for_ui(g)
          d =
            if g.respond_to?(:display_date_for_show)
              g.display_date_for_show
            elsif g.respond_to?(:next_date)
              g.next_date
            elsif g.respond_to?(:date)
              g.date
            end

          return nil unless d.present?

          t =
            if g.respond_to?(:next_time)
              g.next_time
            elsif g.respond_to?(:time)
              g.time
            end

          date_str = d.respond_to?(:strftime) ? d.strftime("%Y-%m-%d") : d.to_s
          time_str = format_time_hhmm(t)

          time_str.present? ? "#{date_str} #{time_str}" : date_str
        end

        def format_time_hhmm(t)
          return nil if t.nil?
          return t.strftime("%H:%M") if t.respond_to?(:strftime)

          s = t.to_s.strip
          return nil if s.empty?

          parts = s.split(":")
          return nil if parts.size < 2

          hh = parts[0].to_i.to_s.rjust(2, "0")
          mm = parts[1].to_i.to_s.rjust(2, "0")
          "#{hh}:#{mm}"
        end
      end
    end
  end
end
