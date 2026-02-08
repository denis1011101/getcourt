module Telegram
  module Flows
    module Games
      module Manage
        module EditFlow
          class << self
            def handle_callback(callback)
              data = (callback["data"] || "").to_s
              cb_id = callback["id"]
              from = callback["from"] || {}
              chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
              message_id = callback.dig("message", "message_id")
              poller = Telegram::Poller.new

              case data
              when /\Agame:edit:set:sport:(\d+):(.+):(\d+)\z/
                require "cgi"
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
                nil

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
                nil

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
                header = "Choose court — page #{page}/#{[ pages, 1 ].max}"
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
                  [ { text: label, callback_data: "game:edit:set:court:#{game_id}:#{c.id}:#{msg_id}" } ]
                end

                nav = []
                nav << [ { text: "‹ Prev", callback_data: "game:edit:court:page:#{game_id}:#{page - 1}:#{msg_id}" } ] if page > 1
                nav << [ { text: "Next ›", callback_data: "game:edit:court:page:#{game_id}:#{page + 1}:#{msg_id}" } ] if page < pages
                buttons.concat(nav) unless nav.empty?

                buttons << [ { text: "Back to edit", callback_data: "game:edit:show:#{game_id}:#{msg_id}" } ]

                if msg_id && msg_id > 0
                  Telegram::Api.edit_message_with_buttons(chat_id, msg_id, header, buttons) rescue nil
                else
                  Telegram::Api.send_with_buttons(chat_id, header, buttons) rescue nil
                end
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
                nil

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
                nil

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

                state = { game_id: game_id, field: field, step: "field", msg_id: message_id, chat_id: chat_id.to_s }
                Rails.cache.write("telegram:edit:chat:#{chat_id}", state, expires_in: 30.minutes)
                Rails.cache.write("telegram:edit:msg:#{message_id}", state, expires_in: 30.minutes) if message_id

                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil

                if field == "sport"
                  require "cgi"
                  buttons = User::SPORTS.each_slice(2).map do |row|
                    row.map { |s| { text: s, callback_data: "game:edit:set:sport:#{game_id}:#{CGI.escape(s)}:#{message_id}" } }
                  end
                  buttons << [ { text: "Cancel", callback_data: "game:edit:cancel:#{game_id}:#{message_id}" } ]
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
                    [ { text: "2", callback_data: "game:edit:set:players_count:#{game_id}:2:#{message_id}" } ],
                    [ { text: "4", callback_data: "game:edit:set:players_count:#{game_id}:4:#{message_id}" } ],
                    [ { text: "Cancel", callback_data: "game:edit:cancel:#{game_id}:#{message_id}" } ]
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
                  page = 1
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
                  callback_page = { "data" => "game:edit:court:page:#{game_id}:#{page}:#{message_id}", "from" => callback["from"], "message" => callback["message"] }
                  handle_callback(callback_page) rescue nil
                else
                  if message_id
                    poller.send_api("editMessageText", {
                      chat_id: chat_id,
                      message_id: message_id,
                      text: "Send new value for #{label}:",
                      reply_markup: { inline_keyboard: [ [ { text: "Cancel", callback_data: "game:edit:cancel:#{game_id}:#{message_id}" } ] ] }
                    }) rescue nil
                  else
                    poller.send_api("sendMessage", { chat_id: chat_id, text: "Send new value for #{label}:" }) rescue nil
                  end
                end
                nil

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
                nil

              when /\Agame:edit:cancel:(\d+):(\d+)\z/
                Telegram::Flows::Games::EditResponder.handle_cancel(callback) rescue nil
                nil

              when /\Agame:edit:confirm:(\d+)\z/
                gid = $1.to_i
                poller.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
                Telegram::Handlers::GamesHandler.show_game(chat_id, gid, 1, message_id: message_id) rescue nil
                nil

              else
                nil
              end
            rescue => e
              Rails.logger.error "[Telegram::Flows::Games::Manage::EditFlow] #{e.class} #{e.message}"
              nil
            end
          end
        end
      end
    end
  end
end
