module Telegram
  module Flows
    module Games
      module ManageFlow
        class << self
          def handle_callback(callback)
            data = (callback["data"] || "").to_s
            cb_id = callback["id"]
            from = callback["from"] || {}
            chat_id = (callback.dig("message","chat","id") || from["id"]).to_s
            message_id = callback.dig("message","message_id")
            poller = Telegram::Poller.new

          case data
          # create-game interactive buttons -> delegate to EditPrompter / handle locally (avoid recursion)
          when /\Agame:create:field:(\w+):(\d+)\z/
            Rails.logger.debug "[Telegram::Flows::Games::ManageFlow] delegating create field to EditPrompter data=#{data} callback_keys=#{callback.keys.inspect}"
            begin
              Telegram::Flows::Games::EditPrompter.handle_callback(callback)
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::ManageFlow] EditPrompter error: #{e.class} #{e.message}\n#{e.backtrace.first(8).join("\n")}"
              # surface error to user for now
              poller.send_api("sendMessage", { chat_id: chat_id, text: "Internal error handling field: #{e.message}" }) rescue nil
            end
            return

          when /\Agame:create:confirm:(\d+)\z/
            gid = $1.to_i
            Rails.logger.debug "[Telegram::Flows::Games::ManageFlow] create confirm => preview game=#{gid}"
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            Telegram::Handlers::GamesHandler.show_game(chat_id, gid, 1, message_id: message_id) rescue nil
            return

          when /\Agame:edit:confirm:(\d+)\z/
            gid = $1.to_i
            Rails.logger.debug "[Telegram::Flows::Games::ManageFlow] edit confirm => preview game=#{gid}"
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            Telegram::Handlers::GamesHandler.show_game(chat_id, gid, 1, message_id: message_id) rescue nil
            return

          when /\Agame:create:cancel:(\d+)(?::(\d+))?\z/
            gid = $1.to_i
            orig_msg_id = $2 ? $2.to_i : nil
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Create cancelled", show_alert: false }) rescue nil
            # remove draft and restore previous court card if possible
            begin
              game = Game.find_by(id: gid)
              if game
                court_id = game.court_id
                game.destroy rescue nil
                if orig_msg_id && court_id
                  Telegram::Handlers::CourtsHandler.show_court(chat_id, court_id, 1, message_id: orig_msg_id) rescue nil
                end
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::ManageFlow] cancel error: #{e.class} #{e.message}"
            end
            return

          # handle sport selection buttons (update sport and restore edit menu)
          when /\Agame:edit:set:sport:(\d+):(.+):(\d+)\z/
            require 'cgi'
            game_id = $1.to_i
            sport = CGI.unescape($2.to_s)
            msg_id = $3.to_i
            game = Game.find_by(id: game_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            if game
              game.update(sport: sport) rescue nil
              Telegram::Flows::Games::EditPrompter.send_edit_prompts(chat_id, game.id, msg_id) rescue nil
            else
              Telegram::Api.edit_message_text(chat_id, msg_id, "Game not found.") rescue nil
            end
            return

          # handle court selection (from edit flow)
          when /\Agame:edit:set:court:(\d+):(\d+):(\d+)\z/
            game_id = $1.to_i
            court_id = $2.to_i
            msg_id = $3.to_i
            game = Game.find_by(id: game_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            if game
              game.update(court_id: court_id) rescue nil
              Telegram::Flows::Games::EditPrompter.send_edit_prompts(chat_id, game.id, msg_id) rescue nil
            else
              Telegram::Api.edit_message_text(chat_id, msg_id, "Game not found.") rescue nil
            end
            return

          # show courts page for selecting court in edit flow
          when /\Agame:edit:court:page:(\d+):(\d+):(\d+)\z/
            game_id = $1.to_i
            page = $2.to_i < 1 ? 1 : $2.to_i
            msg_id = $3.to_i
            per_page = Telegram::Handlers::CourtsHandler::PER_PAGE rescue 5
            user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
            scope = Court.visible_to(user)
            total = scope.count
            pages = (total.to_f / per_page).ceil
            offset = (page - 1) * per_page
            courts = scope.order("id ASC").offset(offset).limit(per_page)
            header = "Choose court — page #{page}/#{[pages,1].max}"
            if courts.empty?
              if msg_id && msg_id > 0
                Telegram::Api.edit_message_text(chat_id, msg_id, "#{header}\n\nNo courts on this page.") rescue nil
              else
                Telegram::Api.send_simple(chat_id, "#{header}\n\nNo courts on this page.") rescue nil
              end
              return
            end

            buttons = courts.map do |c|
              label = (c.respond_to?(:name) && c.name.present?) ? c.name : "Court ##{c.id}"
              [{ text: label, callback_data: "game:edit:set:court:#{game_id}:#{c.id}:#{msg_id}" }]
            end

            nav = []
            nav << [{ text: "‹ Prev", callback_data: "game:edit:court:page:#{game_id}:#{page - 1}:#{msg_id}" }] if page > 1
            nav << [{ text: "Next ›", callback_data: "game:edit:court:page:#{game_id}:#{page + 1}:#{msg_id}" }] if page < pages
            buttons.concat(nav) unless nav.empty?

            buttons << [{ text: "Back to edit", callback_data: "game:edit:show:#{game_id}:#{msg_id}" }]

            if msg_id && msg_id > 0
              Telegram::Api.edit_message_with_buttons(chat_id, msg_id, header, buttons) rescue nil
            else
              Telegram::Api.send_with_buttons(chat_id, header, buttons) rescue nil
            end
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            return

          # handle players_count selection buttons (2 or 4)
          when /\Agame:edit:set:players_count:(\d+):(\d+):(\d+)\z/
            game_id = $1.to_i
            value = $2.to_i
            msg_id = $3.to_i
            game = Game.find_by(id: game_id)
            poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
            if game
              game.update(players_count: value) rescue nil
              Telegram::Flows::Games::EditPrompter.send_edit_prompts(chat_id, game.id, msg_id) rescue nil
            else
              Telegram::Api.edit_message_text(chat_id, msg_id, "Game not found.") rescue nil
            end
            return

            when /\Agame:join:(\d+)\z/
              game = Game.find_by(id: $1.to_i)
              user = User.find_by(telegram_chat_id: chat_id.to_s)
              unless game && user
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Game or user not found", show_alert: false }) rescue nil
                return
              end

              begin
                Participation.find_or_create_by!(game: game, user: user)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "You have entered the game", show_alert: false }) rescue nil
                Telegram::ParticipationNotifier.notify_owner(game, user, action: :joined) rescue nil
              rescue => e
                Rails.logger.error "[GamesFlow] join error: #{e.class} #{e.message}"
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Failed to join the game", show_alert: true }) rescue nil
              end
              Telegram::Handlers::GamesHandler.show_game(chat_id, game.id, 1, message_id: message_id) rescue nil
              return

            when /\Agame:leave:(\d+)\z/
              game = Game.find_by(id: $1.to_i)
              user = User.find_by(telegram_chat_id: chat_id.to_s)
              unless game && user
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Game or user not found", show_alert: false }) rescue nil
                return
              end

              begin
                participation = Participation.find_by(game: game, user: user)
                if participation
                  participation.destroy
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "You have left the game", show_alert: false }) rescue nil
                  Telegram::ParticipationNotifier.notify_owner(game, user, action: :left) rescue nil
                else
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "You are not in the game", show_alert: false }) rescue nil
                end
              rescue => e
                Rails.logger.error "[GamesFlow] leave error: #{e.class} #{e.message}"
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Failed to leave the game", show_alert: true }) rescue nil
              end

              Telegram::Handlers::GamesHandler.show_game(chat_id, game.id, 1, message_id: message_id) rescue nil
              return

            when /\Agame:edit:(\d+)\z/
              start_edit_game(chat_id, $1.to_i, cb_id: cb_id, message_id: message_id)
              return

            # per-field edit: show ForceReply for a single field
            when /\Agame:edit:field:(\d+):([a-z_]+)\z/
              game_id = $1.to_i
              field = $2.to_s
              game = Game.find_by(id: game_id)
              user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
              unless game && user && (user.admin? || user.id == game.user_id)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No permission or game not found", show_alert: true }) rescue nil
                return
              end

              label =
                case field
                when "date" then "date (YYYY-MM-DD)"
                when "time" then "time (HH:MM)"
                when "players_count" then "players count (integer)"
                when "sport" then "sport"
                when "court_id" then "court id (integer)"
                else field
                end

              # store edit state so EditResponder will handle the reply
              state = { game_id: game_id, field: field, step: "field", msg_id: message_id, chat_id: chat_id.to_s }
              Rails.cache.write("telegram:edit:chat:#{chat_id}", state, expires_in: 30.minutes)
              Rails.cache.write("telegram:edit:msg:#{message_id}", state, expires_in: 30.minutes) if message_id

              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil

              # Edit the original message into the prompt (no new message / no ForceReply).
              # For sport — present choice buttons instead of free-text input.
              if field == "sport"
                require 'cgi'
                buttons = User::SPORTS.each_slice(2).map do |row|
                  row.map { |s| { text: s, callback_data: "game:edit:set:sport:#{game_id}:#{CGI.escape(s)}:#{message_id}" } }
                end
                buttons << [{ text: "Cancel", callback_data: "game:edit:cancel:#{game_id}:#{message_id}" }]
                if message_id
                  poller.send_api("editMessageText", {
                    chat_id: chat_id,
                    message_id: message_id,
                    text: "Choose new sport:",
                    reply_markup: { inline_keyboard: buttons }
                  }) rescue nil
                else
                  poller.send_api("sendMessage", { chat_id: chat_id, text: "Choose new sport:", reply_markup: { inline_keyboard: buttons } }) rescue nil
                end

              elsif field == "players_count"
                buttons = [
                  [{ text: "2", callback_data: "game:edit:set:players_count:#{game_id}:2:#{message_id}" }],
                  [{ text: "4", callback_data: "game:edit:set:players_count:#{game_id}:4:#{message_id}" }],
                  [{ text: "Cancel", callback_data: "game:edit:cancel:#{game_id}:#{message_id}" }]
                ]
                if message_id
                  poller.send_api("editMessageText", {
                    chat_id: chat_id,
                    message_id: message_id,
                    text: "Choose players count:",
                    reply_markup: { inline_keyboard: buttons }
                  }) rescue nil
                else
                  poller.send_api("sendMessage", { chat_id: chat_id, text: "Choose players count:", reply_markup: { inline_keyboard: buttons } }) rescue nil
                end

              elsif field == "court_id"
                # show first page of courts with selection callbacks
                page = 1
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
                # delegate to our page handler to render
                callback_page = { "data" => "game:edit:court:page:#{game_id}:#{page}:#{message_id}", "from" => callback["from"], "message" => callback["message"] }
                handle_callback(callback_page) rescue nil

              else
                # generic field: edit original message into prompt (no new message)
                if message_id
                  poller.send_api("editMessageText", {
                    chat_id: chat_id,
                    message_id: message_id,
                    text: "Send new value for #{label}:",
                    reply_markup: { inline_keyboard: [[{ text: "Cancel", callback_data: "game:edit:cancel:#{game_id}:#{message_id}" }]] }
                  }) rescue nil
                else
                  poller.send_api("sendMessage", { chat_id: chat_id, text: "Send new value for #{label}:" }) rescue nil
                end
              end
              return

            when /\Agame:edit:show:(\d+):(\d+)\z/
              game_id = $1.to_i
              msg_id = $2.to_i
              game = Game.find_by(id: game_id)
              user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
              unless game && user && (user.admin? || user.id == game.user_id)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No permission or game not found", show_alert: true }) rescue nil
                return
              end
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
              Telegram::Flows::Games::EditPrompter.send_edit_prompts(chat_id, game.id, msg_id) rescue nil
              return

            when /\Agame:edit:cancel:(\d+):(\d+)\z/
              # cancel in-progress edit prompts
              Telegram::Flows::Games::EditResponder.handle_cancel(callback) rescue nil
              return

            when /\Agame:delete:(\d+)(?::(\d+))?\z/
              game_id = $1.to_i
              page = ($2 || 1).to_i
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
              delete_game(chat_id, game_id, page, message_id: message_id)
              return

            when /\Agame:create\z/
              start_create_game(chat_id, cb_id: cb_id)
              return

            else
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Unknown manage action", show_alert: false }) rescue nil
              return
            end
          rescue => e
            Rails.logger.error "[Telegram::Flows::Games::ManageFlow] callback error: #{e.class} #{e.message}"
          end

          # Start create game flow (from menu)
          def start_create_game(chat_id, cb_id: nil)
            poller = Telegram::Poller.new
            user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
            if user
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Create game — reply with details", show_alert: false }) rescue nil
              poller.send_api("sendMessage", {
                chat_id: chat_id,
                text: "GAME_PROMPT\nReply with: date(YYYY-MM-DD) time(HH:MM) players_count sport [court_id]\nExample:\n2025-12-10 19:00 4 tennis 12",
                reply_markup: { force_reply: true, selective: true }
              })
            else
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No linked account. Send /start first.", show_alert: false }) rescue nil
            end
          end

          # Initiate edit-game flow (permission check)
          def start_edit_game(chat_id, game_id, cb_id: nil, message_id: nil)
            poller = Telegram::Poller.new
            game = Game.find_by(id: game_id)
            unless game
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "Game not found", show_alert: false }) rescue nil
              return
            end
            user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
            unless user && (user.admin? || user.id == game.user_id)
              poller.send_api("answerCallbackQuery", { callback_query_id: cb_id, text: "No permission to edit", show_alert: true }) rescue nil
              return
            end

            # delegate prompt messages to helper
            Telegram::Flows::Games::EditPrompter.send_edit_prompts(chat_id, game_id, message_id)
          end

          # Delete a game (permission check)
          def delete_game(chat_id, game_id, page = 1, message_id: nil)
            poller = Telegram::Poller.new
            game = Game.find_by(id: game_id)
            unless game
              if message_id
                Telegram::Api.edit_message_text(chat_id, message_id, "Game not found.") rescue nil
              else
                poller.send_api("sendMessage", { chat_id: chat_id, text: "Game not found." }) rescue nil
              end
              return
            end
            user = User.find_by(telegram_chat_id: chat_id.to_s) rescue nil
            unless user && (user.admin? || user.id == game.user_id)
              if message_id
                Telegram::Api.edit_message_text(chat_id, message_id, "No permission to delete this game.") rescue nil
              else
                poller.send_api("sendMessage", { chat_id: chat_id, text: "No permission to delete this game." }) rescue nil
              end
              return
            end

            game.destroy
            poller.send_api("answerCallbackQuery", { callback_query_id: nil }) rescue nil
            # show updated list by editing the original message if possible
            Telegram::Handlers::GamesHandler.list_page(chat_id, page, message_id: message_id)
          end
        end
      end
    end
  end
end
