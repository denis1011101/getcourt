module Telegram
  module Handlers
    class GamesHandler
      PER_PAGE = 5

      class << self
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

        # Return label used in games lists (shared formatter used everywhere)
        def game_label(g)
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

          sport = if g.respond_to?(:has_attribute?) && g.has_attribute?(:sport)
                    g.sport.to_s.strip.presence
                  elsif g.respond_to?(:sport)
                    g.sport.to_s.strip.presence
                  end

          required = (g.respond_to?(:players_count) && g.players_count.to_i > 0) ? g.players_count.to_i : 4
          taken = (g.respond_to?(:participations) ? g.participations.size : 0)
          spots_left = required - taken
          spots_text = "#{spots_left} spot#{'s' if spots_left != 1} left — #{taken}/#{required}"
          parts = [sport, date, spots_text].compact
          label = parts.join(" — ")
          label.presence || (g.respond_to?(:title) ? g.title.to_s.presence || "Game ##{g.id}" : "Game ##{g.id}")
        end

        # Send a page with list of games
        def list_page(chat_id, page = 1, message_id: nil)
          page = page.to_i < 1 ? 1 : page.to_i
          total = Game.count
          pages = (total.to_f / PER_PAGE).ceil
          offset = (page - 1) * PER_PAGE
          games = Game.order("id DESC").offset(offset).limit(PER_PAGE)

          header = "Games — page #{page}/#{[pages, 1].max}"

          if games.empty?
            if message_id
              Telegram::Api.edit_message_text(chat_id, message_id, "#{header}\n\nNo games on this page.") and return
            else
              Telegram::Api.send_simple(chat_id, "#{header}\n\nNo games on this page.") and return
            end
          end

          buttons = games.map do |g|
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

            # sport
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
            label = label.presence || "Game ##{g.id}"

            [{ text: label, callback_data: "game:show:#{g.id}:#{page}" }]
          end

          nav = []
          nav << [{ text: "‹ Prev", callback_data: "menu:games:page:#{page - 1}" }] if page > 1
          nav << [{ text: "Next ›", callback_data: "menu:games:page:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?

            # + main menu
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
          lines << ("When: #{game.starts_at}" if game.respond_to?(:starts_at) && game.starts_at)
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

          buttons << [{ text: "Back to list", callback_data: "menu:games:page:#{page}" }]
          buttons << [{ text: "Main menu", callback_data: "menu:main" }]

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
