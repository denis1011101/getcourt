module Telegram
  module Handlers
    class GamesHandler
      PER_PAGE = 5

      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          buttons = [
            [ { text: t.(:all_games),    callback_data: "menu:games:page:1" } ],
            [ { text: t.(:create_game),  callback_data: "game:create" } ],
            [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]
          ]
          send_or_edit_with_buttons(chat_id, t.(:games_menu), buttons, message_id: message_id)
        end

        def owner_display(user)
          Telegram::Helpers::UserLookup.display_name(user)
        end

        # Return label used in games lists (shared formatter used everywhere)
        # locale: pass the active locale so spots-left text is correctly localised
        def game_label(g, owner: nil, locale: Telegram::I18n::DEFAULT_LOCALE)
          date = Telegram::Helpers::GameFormatting.game_datetime(g)
          title = Telegram::Helpers::GameFormatting.game_title(g)

          required = (g.respond_to?(:players_count) && g.players_count.to_i > 0) ? g.players_count.to_i : 4
          approved_count =
            if g.participations.loaded?
              g.participations.select { |p| p.respond_to?(:approved?) ? p.approved? : (p.status == "approved") }.size
            else
              g.participations.respond_to?(:approved) ? g.participations.approved.count : g.participations.count
            end
          taken = approved_count
          spots_left = required - taken
          spots_left = 0 if spots_left.negative?
          spots_text = Telegram::I18n.spots_left_text(spots_left, locale: locale)

          # Always add game ID to title/sport
          title_with_id = "#{title || (g.respond_to?(:title) && g.title.to_s.presence) || 'Game'} ##{g.id}"
          parts = [ title_with_id, date, spots_text ].compact
          parts.join(" — ")
        end

        # Send a page with list of games
        def list_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

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

            same_city = if user_city && g.court&.city_name.to_s.strip.downcase == user_city
                          0
            else
                          1
            end

            { game: g, date: sort_date, time: hhmm, is_future: is_future, city_rank: same_city }
          end

          future_items, past_items = mapped_games.partition { |item| item[:is_future] }

          sorter = ->(item) { [ item[:date], item[:time] ] }

          sorted_future = future_items.sort_by(&sorter)
          sorted_past   = past_items.sort_by(&sorter)

          sorted_games = (sorted_future + sorted_past).map { |item| item[:game] }

          total = sorted_games.size
          pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
          offset = (page - 1) * PER_PAGE
          games = sorted_games.slice(offset, PER_PAGE) || []

          header = t.(:games_page, page: page, pages: pages)

          if games.empty?
            send_or_edit_text(chat_id, "#{header}\n\n#{t.(:no_games_on_page)}", message_id: message_id)
            return
          end

          buttons = games.map do |g|
            [ { text: game_label(g, locale: locale), callback_data: "game:show:#{g.id}:#{page}" } ]
          end

          nav = []
          nav << [ { text: t.(:prev_page), callback_data: "menu:games:page:#{page - 1}" } ] if page > 1
          nav << [ { text: t.(:next_page), callback_data: "menu:games:page:#{page + 1}" } ] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        # Show game card with action buttons (join, prebook, edit/delete if owner/admin, back)
        def show_game(chat_id, game_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          Rails.logger.debug "[Telegram::Handlers::GamesHandler] show_game chat=#{chat_id} game_id=#{game_id} page=#{page} msg_id=#{message_id}"
          game = Game.find_by(id: game_id)
          return Telegram::Api.send_simple(chat_id, t.(:game_not_found)) unless game

          # participants / owner info
          participants_count =
            if game.respond_to?(:participations)
              game.participations.respond_to?(:approved) ? game.participations.approved.size : game.participations.size
            else
              0
            end
          capacity = (game.respond_to?(:players_count) && game.players_count.to_i > 0) ? game.players_count.to_i : "?"
          players_line = t.(:players, count: participants_count, capacity: capacity)
          owner = User.find_by(id: game.user_id) rescue nil
          owner_name = Telegram::Helpers::UserLookup.display_name(owner, fallback: owner&.telegram_chat_id || "—")
          owner_line = t.(:owner, name: owner_name)

          host = ENV.fetch("APP_HOST", "https://getcourt.co")
          game_url = Rails.application.routes.url_helpers.game_url(game, host: host)

          lines = []
          title = Telegram::Helpers::GameFormatting.game_title(game)

          title_text = "#{title || 'Game'} ##{game.id}"
          lines << "*#{title_text}*"

          coach = coach_badge_for(game, locale)
          lines << t.(:coach_label, value: coach) if coach.present?

          when_str = Telegram::Helpers::GameFormatting.game_datetime(game)
          lines << t.(:when_label, datetime: when_str) if when_str.present?

          lines << players_line
          lines << t.(:court_label, name: game.court&.name) if game.respond_to?(:court) && game.court
          lines << owner_line
          text = lines.compact.join("\n")

          buttons = []

          user = Telegram::Helpers::UserLookup.find_user(chat_id)

          participation = user ? game.participations.find_by(user_id: user.id) : nil
          direct_join = user && (user.admin? || user.id == game.user_id)
          join_btn =
            if participation && participation.respond_to?(:pending?) && participation.pending?
              { text: t.(:request_sent), callback_data: "game:join_pending:#{game.id}" }
            elsif participation
              { text: t.(:leave), callback_data: "game:leave:#{game.id}" }
            else
              label = direct_join ? t.(:join) : t.(:request_to_join)
              { text: label, callback_data: "game:join:#{game.id}" }
            end

          row1 = [ join_btn ]

          if game.prebooking_enabled? && (!game.respond_to?(:recurring?) || game.recurring?)
            row1 << { text: t.(:prebooking), callback_data: "game:prebook:#{game.id}" }
          end

          buttons << row1

          can_fill_stats = user && (user.admin? || user.id == game.user_id)

          # inline players list (same message)
          buttons << [ { text: t.(:players_list_btn), callback_data: "game:players:#{game.id}:#{page}" } ]

          if game.started_for_ui?
            if can_fill_stats
              buttons << [ { text: t.(:statistics), callback_data: "tg_fill:#{game.id}:#{page}" } ]
            else
              buttons << [ { text: t.(:statistics), callback_data: "tg_stats_unauthorized:#{game.id}" } ]
            end
          else
            buttons << [ { text: t.(:statistics_locked), callback_data: "tg_stats_locked:#{game.id}" } ]
          end

          if user && (user.admin? || user.id == game.user_id)
            buttons << [ { text: t.(:invite_players), callback_data: "game:invite:#{game.id}" } ]
            buttons << [ { text: t.(:manage_players), callback_data: "game:manage:#{game.id}:#{page}" } ]
            buttons << [ { text: t.(:edit), callback_data: "game:edit:#{game.id}" } ]
            buttons << [ { text: t.(:delete), callback_data: "game:delete:#{game.id}:#{page}" } ]
          end

          buttons << [ { text: t.(:open_in_browser), url: game_url } ] unless host.to_s.include?("localhost")

          buttons << [ { text: t.(:back_to_games), callback_data: "menu:games:page:#{page}" } ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        # Show players list with brief stats, inline (same message)
        def show_players(chat_id, game_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          game = Game.find_by(id: game_id)
          return Telegram::Api.send_simple(chat_id, t.(:game_not_found)) unless game

          users = []
          users << game.user if game.respond_to?(:user)
          if game.respond_to?(:participations)
            scope = game.participations.respond_to?(:approved) ? game.participations.approved : game.participations
            users.concat(scope.includes(:user).map(&:user))
          end
          users = users.compact.uniq { |u| u.id }

          lines = []
          lines << "*#{t.(:players_list_title, game_id: game.id)}*"
          lines << ""

          if users.empty?
            lines << t.(:players_list_empty)
          else
            rows = users.map do |u|
              ps = u.player_statistic
              total_games = ps&.singles_games.to_i + ps&.doubles_games.to_i
              total_wins  = ps&.singles_wins.to_i + ps&.doubles_wins.to_i
              pct = total_games > 0 ? (total_wins.to_f / total_games * 100).round(1) : 0.0
              name = u.telegram_username.present? ? "@#{u.telegram_username.delete_prefix('@')}" : (u.name.presence || u.email.presence || "User ##{u.id}")
              { name: name, games: total_games, wins: total_wins, pct: pct }
            end
            rows.sort_by! { |r| [ -r[:pct], -r[:wins], -r[:games] ] }
            rows.each do |r|
              lines << t.(:player_stats_row, name: r[:name], games: r[:games], wins: r[:wins], pct: r[:pct])
            end
          end

          text = lines.join("\n")

          buttons = [
            [ { text: t.(:back_to_game), callback_data: "game:show:#{game.id}:#{page}" } ]
          ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        private

        def coach_badge_for(game, locale = "ru")
          return nil unless game
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          if game.respond_to?(:with_coach?) && game.with_coach?
            t.(:coach_with)
          elsif game.respond_to?(:needs_coach?) && game.needs_coach?
            t.(:coach_need)
          elsif game.respond_to?(:with_coach?) || game.respond_to?(:needs_coach?)
            t.(:coach_no)
          else
            nil
          end
        end

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
