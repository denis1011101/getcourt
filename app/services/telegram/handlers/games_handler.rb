module Telegram
  module Handlers
    class GamesHandler
      PER_PAGE = 5

      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          buttons = [
            [ { text: "All games",   callback_data: "menu:games:page:1" } ],
            [ { text: "Create game", callback_data: "game:create" } ],
            [ { text: "Main menu",  callback_data: "menu:main" } ]
          ]
          send_or_edit_with_buttons(chat_id, "Games menu:", buttons, message_id: message_id)
        end

        def owner_display(user)
          Telegram::Helpers::UserLookup.display_name(user)
        end

        # Return label used in games lists (shared formatter used everywhere)
        # owner: override whose nick is shown (default: game.user)
        def game_label(g, owner: nil)
          date = Telegram::Helpers::GameFormatting.game_datetime(g)
          title = Telegram::Helpers::GameFormatting.game_title(g)

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

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          user_city = user&.city_name.to_s.strip.downcase.presence

          all_games = Game.includes(:user, :participations, :prebooking_cancellations)
                          .where("recurring = ? OR date >= ?", true, Date.current)
                          .to_a

          today = Date.current
          now = Time.zone.now
          now_hhmm = now.hour * 100 + now.min

          mapped_games = all_games.map do |g|
            d = g.display_date_for_show
            sort_date = d || Date.new(9999, 12, 31)

            t_obj = Telegram::Helpers::GameFormatting.resolve_time(g)
            hhmm = 0
            if t_obj.respond_to?(:strftime)
              hhmm = t_obj.strftime("%H%M").to_i
            elsif t_obj.to_s.include?(":")
              parts = t_obj.to_s.split(":")
              hhmm = parts[0].to_i * 100 + parts[1].to_i
            end

            is_future = if sort_date > today
                          true
                        elsif sort_date < today
                          false
                        else
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

          future_items, past_items = mapped_games.partition { |item| item[:is_future] }

          sorter = ->(item) { [item[:date], item[:time]] }

          sorted_future = future_items.sort_by(&sorter)
          sorted_past   = past_items.sort_by(&sorter)

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

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
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
          owner_name = Telegram::Helpers::UserLookup.display_name(owner, fallback: owner&.telegram_chat_id || "—")
          owner_line = "Owner: #{owner_name}"

          host = ENV.fetch("APP_HOST", "https://getcourt.co")
          game_url = Rails.application.routes.url_helpers.game_url(game, host: host)

          lines = []
          title = Telegram::Helpers::GameFormatting.game_title(game)

          # always show either the title/sport or fallback to "Game", always with game id on the first line
          title_text = "#{title || 'Game'} ##{game.id}"
          lines << "*#{title_text}*"

          coach = coach_badge_for(game)
          lines << "Coach: #{coach}" if coach.present?

          when_str = Telegram::Helpers::GameFormatting.game_datetime(game)
          lines << "When: #{when_str}" if when_str.present?

          lines << players_line
          lines << ("Court: #{game.court&.name}") if game.respond_to?(:court) && game.court
          lines << owner_line
          text = lines.compact.join("\n")

          buttons = []

          user = Telegram::Helpers::UserLookup.find_user(chat_id)

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

          if game.prebooking_enabled? && (!game.respond_to?(:recurring?) || game.recurring?)
            row1 << { text: "Prebooking", callback_data: "game:prebook:#{game.id}" }
          end

          buttons << row1

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

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        private

        def coach_badge_for(game)
          return nil unless game

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

        # Uses the same "occurrence" logic as UI: display_date_for_show -> next_date -> date
        # If time is missing, unlock at start of the day.
        def game_start_at_for_ui(g)
          d = Telegram::Helpers::GameFormatting.resolve_date(g)
          return nil unless d.present?

          t = Telegram::Helpers::GameFormatting.resolve_time(g)

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
            s = Telegram::Helpers::GameFormatting.format_time_hhmm(t)
            if s.present?
              parts = s.split(":")
              hh = parts[0].to_i
              mm = parts[1].to_i
            end
          end

          Time.zone.local(date.year, date.month, date.day, hh, mm, 0)
        end
      end
    end
  end
end
