module Telegram
  module Handlers
    class CourtsHandler
      PER_PAGE = 5

      class << self
        def menu(chat_id, message_id: nil)
          buttons = [
            [{ text: "All courts",   callback_data: "menu:courts:page:1" }],
            [{ text: "Main menu",  callback_data: "menu:main" }]
            # [{ text: "Create court", callback_data: "court:create" }]
          ]
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "Courts menu:", buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, "Courts menu:", buttons)
          end
        end

        # Return label used in games lists (shared formatter used everywhere)
        def game_label(g)
          # date/time
          date =
            if g.respond_to?(:has_attribute?) && g.has_attribute?(:starts_at) && g.starts_at
              g.starts_at.respond_to?(:strftime) ? g.starts_at.strftime("%Y-%m-%d %H:%M") : g.starts_at.to_s
            elsif g.respond_to?(:starts_at) && g.starts_at
              g.starts_at.to_s
            elsif g.respond_to?(:date) && g.respond_to?(:time) && (g.date.present? || g.time.present?)
              dt = []
              dt << (g.date.respond_to?(:strftime) ? g.date.strftime("%Y-%m-%d") : g.date.to_s) if g.date.present?
              dt << (g.time.respond_to?(:strftime) ? g.time.strftime("%H:%M") : g.time.to_s) if g.time.present?
              dt.join(" ")
            else
              nil
            end

          # sport/title
          sport = if g.respond_to?(:has_attribute?) && g.has_attribute?(:sport)
                    g.sport.to_s.strip.presence
                  elsif g.respond_to?(:sport)
                    g.sport.to_s.strip.presence
                  end

          # spots left / ratio
          required = (g.respond_to?(:players_count) && g.players_count.to_i > 0) ? g.players_count.to_i : 4
          taken = (g.respond_to?(:participations) ? g.participations.size : 0)
          spots_left = required - taken
          spots_text = "#{spots_left} spot#{'s' if spots_left != 1} left — #{taken}/#{required}"

          parts = [sport, date, spots_text].compact
          label = parts.join(" — ")
          label.presence || (g.respond_to?(:title) ? g.title.to_s.presence || "Game ##{g.id}" : "Game ##{g.id}")
        end

        # Send a page with list of courts
        def list_page(chat_id, page = 1, message_id: nil)
          page = page.to_i < 1 ? 1 : page.to_i
          total = Court.count
          pages = (total.to_f / PER_PAGE).ceil
          offset = (page - 1) * PER_PAGE
          courts = Court.order("id ASC").offset(offset).limit(PER_PAGE)
          header = "Courts — page #{page}/#{[pages, 1].max}"

          if courts.empty?
            if message_id
              Telegram::Api.edit_message_text(chat_id, message_id, "#{header}\n\nNo courts on this page.") and return
            else
              Telegram::Api.send_simple(chat_id, "#{header}\n\nNo courts on this page.") and return
            end
          end

          buttons = courts.map do |c|
            label = (c.respond_to?(:name) && c.name.present?) ? c.name : "Court ##{c.id}"
            [{ text: label, callback_data: "court:show:#{c.id}:#{page}" }]
          end

          nav = []
          nav << [{ text: "‹ Prev", callback_data: "menu:courts:page:#{page - 1}" }] if page > 1
          nav << [{ text: "Next ›", callback_data: "menu:courts:page:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?

          # + main menu
          buttons << [{ text: "Main menu", callback_data: "menu:main" }]

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, header, buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, header, buttons)
          end
        end

        # List games for a specific court with pagination (5 per page)
        def list_games(chat_id, court_id, page = 1, message_id: nil)
          page = page.to_i < 1 ? 1 : page.to_i
          per_page = 5
          total = Game.where(court_id: court_id).count
          pages = (total.to_f / per_page).ceil
          offset = (page - 1) * per_page
          games = Game.where(court_id: court_id).order(date: :desc).offset(offset).limit(per_page)
          header = "Games on court ##{court_id} — page #{page}/#{[pages,1].max}"

          if games.empty?
            if message_id
              Telegram::Api.edit_message_text(chat_id, message_id, "#{header}\n\nNo games on this page.") and return
            else
              Telegram::Api.send_simple(chat_id, "#{header}\n\nNo games on this page.") and return
            end
          end
          buttons = games.map do |g|
            label = Telegram::Handlers::GamesHandler.game_label(g)
            [{ text: label, callback_data: "game:show:#{g.id}:1" }]
          end

          nav = []
          nav << [{ text: "‹ Prev", callback_data: "court:games:#{court_id}:#{page - 1}" }] if page > 1
          nav << [{ text: "Next ›", callback_data: "court:games:#{court_id}:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?

          # add Back to court button
          buttons << [{ text: "Back to court", callback_data: "court:show:#{court_id}:#{page}" }]

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, header, buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, header, buttons)
          end
        end

        # Show court card with action buttons (create game, edit if owner/admin, back)
        def show_court(chat_id, court_id, page = 1, message_id: nil)
          court = Court.find_by(id: court_id)
          return Telegram::Api.send_simple(chat_id, "Court not found.") unless court

          header = "Court ##{court.id}"
          text = "#{header}\n\n#{court.name.to_s}"

          buttons = []
          # create game (keep if enabled)
          buttons << [{ text: "Create game", callback_data: "create_game_from_court:#{court.id}" }]
          # list games on this court (pagination handled by courts_flow -> CourtsHandler.list_games)
          buttons << [{ text: "List of games", callback_data: "court:games:#{court.id}:1" }]
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons)
          end
        end
      end
    end
  end
end
