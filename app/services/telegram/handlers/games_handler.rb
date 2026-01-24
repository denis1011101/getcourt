module Telegram
  module Handlers
    class GamesHandler
      PER_PAGE = 5

      class << self
        extend Telegram::Handlers::ReplyHelpers

        def menu(chat_id, message_id: nil)
          buttons = [
            [{ text: "All games",   callback_data: "menu:games:page:1" }],
            [{ text: "Create game", callback_data: "game:create" }],
            [{ text: "Main menu",  callback_data: "menu:main" }]
          ]
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "Games menu:", buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, "Games menu:", buttons)
          end
        end

        def owner_display(user)
          return nil unless user

          user.name.to_s.strip.presence ||
            user.username.to_s.strip.presence ||
            user.telegram_username.to_s.strip.presence ||
            "User"
        end

        # Return label used in games lists (shared formatter used everywhere)
        def game_label(g)
          date = game_datetime_for_ui(g)

          sport =
            if g.respond_to?(:has_attribute?) && g.has_attribute?(:sport)
              g.sport.to_s.strip.presence
            elsif g.respond_to?(:sport)
              g.sport.to_s.strip.presence
            end

          owner = owner_display(g.respond_to?(:user) ? g.user : nil)

          required = (g.respond_to?(:players_count) && g.players_count.to_i > 0) ? g.players_count.to_i : 4
          taken = (g.respond_to?(:participations) ? g.participations.size : 0)
          spots_left = required - taken
          spots_left = 0 if spots_left.negative?
          spots_text = "#{spots_left} spot#{'s' if spots_left != 1} left"

          parts = [sport, owner, date, spots_text].compact
          label = parts.join(" — ")
          label.presence || (g.respond_to?(:title) ? g.title.to_s.presence || "Game ##{g.id}" : "Game ##{g.id}")
        end

        # Send a page with list of games
        def list_page(chat_id, page = 1, message_id: nil)
          page = page.to_i < 1 ? 1 : page.to_i
          total = Game.count
          pages = (total.to_f / PER_PAGE).ceil
          offset = (page - 1) * PER_PAGE
          games = Game.includes(:user, :participations).order("id DESC").offset(offset).limit(PER_PAGE)

          header = "Games — page #{page}/#{[pages, 1].max}"

          if games.empty?
            send_or_edit_text(chat_id, "#{header}\n\nNo games on this page.", message_id: message_id)
            return
          end

          buttons = games.map do |g|
            [{ text: game_label(g), callback_data: "game:show:#{g.id}:#{page}" }]
          end

          nav = []
          nav << [{ text: "‹ Prev", callback_data: "menu:games:page:#{page - 1}" }] if page > 1
          nav << [{ text: "Next ›", callback_data: "menu:games:page:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [{ text: "Main menu", callback_data: "menu:main" }]

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
          participants_count = game.respond_to?(:participations) ? game.participations.size : 0
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

          lines = []
          # safe title extraction
          title =
            if game.respond_to?(:has_attribute?) && game.has_attribute?(:title)
              game.title.to_s.strip.presence
            else
              (game.respond_to?(:sport) && game.sport.to_s.strip.presence)
            end
          title ||= "Game ##{game.id}"
          lines << "*#{title}*"

          when_str = game_datetime_for_ui(game)
          lines << "When: #{when_str}" if when_str.present?

          lines << players_line
          lines << ("Court: #{game.court&.name}") if game.respond_to?(:court) && game.court
          lines << owner_line
          text = lines.compact.join("\n")

          buttons = []

          user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil

          join_btn =
            if user && game.participations.exists?(user_id: user.id)
              { text: "Leave", callback_data: "game:leave:#{game.id}" }
            else
              { text: "Join", callback_data: "game:join:#{game.id}" }
            end

          row1 = [join_btn]

          # показываем пребукинг только когда включён
          if game.prebooking_enabled? && (!game.respond_to?(:recurring?) || game.recurring?)
            row1 << { text: "Prebooking", callback_data: "game:prebook:#{game.id}" }
          end

          buttons << row1

          if user && (user.admin? || user.id == game.user_id)
            buttons << [{ text: "Invite players", callback_data: "game:invite:#{game.id}" }]
            buttons << [{ text: "Manage players", callback_data: "game:manage:#{game.id}:#{page}" }]
            buttons << [{ text: "Edit", callback_data: "game:edit:#{game.id}" }]
            buttons << [{ text: "Delete", callback_data: "game:delete:#{game.id}:#{page}" }]
          end

          buttons << [{ text: "Back to games", callback_data: "menu:games:page:#{page}" }]

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons)
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons)
          end
        end

        private

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
