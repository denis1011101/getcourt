module Telegram
  module Handlers
    class CourtsHandler
      PER_PAGE = 5

      class << self
        include Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          buttons = [
            [{ text: "All courts",   callback_data: "menu:courts:page:1" }],
            [{ text: "Main menu",  callback_data: "menu:main" }]
            # [{ text: "Create court", callback_data: "court:create" }]
          ]

          send_or_edit_with_buttons(chat_id, "Courts menu:", buttons, message_id: message_id)
        end

        # Use the shared formatter (uses display_date_for_show / next_date logic)
        def game_label(g)
          Telegram::Handlers::GamesHandler.game_label(g)
        end

        # Send a page with list of courts
        def list_page(chat_id, page = 1, message_id: nil)
          page = page.to_i < 1 ? 1 : page.to_i
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          scope = Court.visible_to(user)
          total = scope.count
          pages = (total.to_f / PER_PAGE).ceil
          offset = (page - 1) * PER_PAGE
          courts = scope.order("id ASC").offset(offset).limit(PER_PAGE)
          header = "Courts — page #{page}/#{[pages, 1].max}"

          if courts.empty?
            send_or_edit_text(chat_id, "#{header}\n\nNo courts on this page.", message_id: message_id)
            return
          end

          buttons = courts.map do |c|
            label = (c.respond_to?(:name) && c.name.present?) ? c.name : "Court ##{c.id}"
            [{ text: label, callback_data: "court:show:#{c.id}:#{page}" }]
          end

          nav = []
          nav << [{ text: "‹ Prev", callback_data: "menu:courts:page:#{page - 1}" }] if page > 1
          nav << [{ text: "Next ›", callback_data: "menu:courts:page:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [{ text: "Main menu", callback_data: "menu:main" }]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        # List games for a specific court with pagination
        def list_games(chat_id, court_id, page = 1, message_id: nil)
          page = page.to_i < 1 ? 1 : page.to_i
          total = Game.where(court_id: court_id).count
          pages = (total.to_f / PER_PAGE).ceil
          offset = (page - 1) * PER_PAGE
          games = Game.where(court_id: court_id).order(date: :desc).offset(offset).limit(PER_PAGE)
          header = "Games on court ##{court_id} — page #{page}/#{[pages, 1].max}"

          if games.empty?
            buttons = [
              [{ text: "Back to court", callback_data: "court:show:#{court_id}:#{page}" }],
              [{ text: "Main menu", callback_data: "menu:main" }]
            ]

            send_or_edit_with_buttons(
              chat_id,
              "#{header}\n\nNo games on this page.",
              buttons,
              message_id: message_id
            )
            return
          end

          buttons = games.map do |g|
            label = Telegram::Handlers::GamesHandler.game_label(g)
            [{ text: label, callback_data: "game:show:#{g.id}:1" }]
          end

          nav = []
          nav << [{ text: "‹ Prev", callback_data: "court:games:#{court_id}:#{page - 1}" }] if page > 1
          nav << [{ text: "Next ›", callback_data: "court:games:#{court_id}:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [{ text: "Back to court", callback_data: "court:show:#{court_id}:#{page}" }]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        # Show court card with action buttons (create game, edit if owner/admin, back)
        def show_court(chat_id, court_id, page = 1, message_id: nil)
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          court = Court.visible_to(user).find_by(id: court_id)
          return Telegram::Api.send_simple(chat_id, "Court not found.") unless court

          header = "Court ##{court.id}"
          text = "#{header}\n\n#{court.name.to_s}"

          buttons = []
          buttons << [{ text: "Create game", callback_data: "create_game_from_court:#{court.id}" }]
          buttons << [{ text: "List of games", callback_data: "court:games:#{court.id}:1" }]

          buttons << [{ text: "Back to courts", callback_data: "menu:courts:page:#{page}" }]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end
      end
    end
  end
end
