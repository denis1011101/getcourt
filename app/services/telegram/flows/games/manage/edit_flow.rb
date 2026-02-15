module Telegram
  module Flows
    module Games
      module Manage
        module EditFlow
          class << self
            include Telegram::Handlers::ReplyHelpers

            def handle_callback(callback)
              cb = Telegram::Helpers::CallbackData.parse(callback)
              poller = Telegram::Poller.new
              locale = Telegram::Helpers::UserLookup.locale_for(cb.chat_id)
              t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

              case cb.data
              when /\Agame:edit:(\d+)\z/
                game_id = $1.to_i
                game = Game.find_by(id: game_id)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless game && user && (user.admin? || user.id == game.user_id)
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:unauthorized_or_not_found), show_alert: true }) rescue nil
                  return
                end
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                Telegram::Flows::Games::EditPrompter.send_edit_prompts(cb.chat_id, game.id, cb.message_id) rescue nil
                nil

              when /\Agame:edit:set:sport:(\d+):(.+):(\d+)\z/
                require "cgi"
                game_id = $1.to_i
                sport = CGI.unescape($2.to_s)
                msg_id = $3.to_i
                game = Game.find_by(id: game_id)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                if game
                  game.update(sport: sport) rescue nil
                  Telegram::Flows::Games::EditPrompter.send_edit_prompts(cb.chat_id, game.id, msg_id) rescue nil
                else
                  Telegram::Api.edit_message_text(cb.chat_id, msg_id, t.(:edit_game_not_found)) rescue nil
                end
                nil

              when /\Agame:edit:set:court:(\d+):(\d+):(\d+)\z/
                game_id = $1.to_i
                court_id = $2.to_i
                msg_id = $3.to_i
                game = Game.find_by(id: game_id)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                if game
                  game.update(court_id: court_id) rescue nil
                  Telegram::Flows::Games::EditPrompter.send_edit_prompts(cb.chat_id, game.id, msg_id) rescue nil
                else
                  Telegram::Api.edit_message_text(cb.chat_id, msg_id, t.(:edit_game_not_found)) rescue nil
                end
                nil

              when /\Agame:edit:court:page:(\d+):(\d+):(\d+)\z/
                game_id = $1.to_i
                page = $2.to_i < 1 ? 1 : $2.to_i
                msg_id = $3.to_i
                per_page = Telegram::Handlers::CourtsHandler::PER_PAGE rescue 5
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                scope = Court.visible_to(user)
                total = scope.count
                pages = (total.to_f / per_page).ceil
                offset = (page - 1) * per_page
                courts = scope.order("id ASC").offset(offset).limit(per_page)
                header = t.(:edit_choose_court_page, page: page, pages: [pages, 1].max)
                if courts.empty?
                  send_or_edit_text(cb.chat_id, "#{header}\n\n#{t.(:edit_no_courts_on_page)}", message_id: msg_id > 0 ? msg_id : nil)
                  return
                end

                buttons = courts.map do |c|
                  label = (c.respond_to?(:name) && c.name.present?) ? c.name : "#{t.(:court_label, name: "##{c.id}")}"
                  [ { text: label, callback_data: "game:edit:set:court:#{game_id}:#{c.id}:#{msg_id}" } ]
                end

                nav = []
                nav << [ { text: t.(:prev_page), callback_data: "game:edit:court:page:#{game_id}:#{page - 1}:#{msg_id}" } ] if page > 1
                nav << [ { text: t.(:next_page), callback_data: "game:edit:court:page:#{game_id}:#{page + 1}:#{msg_id}" } ] if page < pages
                buttons.concat(nav) unless nav.empty?

                buttons << [ { text: t.(:create_court), callback_data: "court:create" } ]
                buttons << [ { text: t.(:edit_back_to_edit), callback_data: "game:edit:show:#{game_id}:#{msg_id}" } ]

                send_or_edit_with_buttons(cb.chat_id, header, buttons, message_id: msg_id > 0 ? msg_id : nil)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                nil

              when /\Agame:edit:set:players_count:(\d+):(\d+):(\d+)\z/
                game_id = $1.to_i
                value = $2.to_i
                msg_id = $3.to_i
                game = Game.find_by(id: game_id)
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                if game
                  game.update(players_count: value) rescue nil
                  Telegram::Flows::Games::EditPrompter.send_edit_prompts(cb.chat_id, game.id, msg_id) rescue nil
                else
                  Telegram::Api.edit_message_text(cb.chat_id, msg_id, t.(:edit_game_not_found)) rescue nil
                end
                nil

              when /\Agame:edit:field:(\d+):([a-z_]+)\z/
                game_id = $1.to_i
                field = $2.to_s
                game = Game.find_by(id: game_id)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless game && user && (user.admin? || user.id == game.user_id)
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:unauthorized_or_not_found), show_alert: true }) rescue nil
                  return
                end

                label =
                  case field
                  when "date" then t.(:edit_field_label_date)
                  when "time" then t.(:edit_field_label_time)
                  when "players_count" then t.(:edit_field_label_players)
                  when "sport" then t.(:edit_field_label_sport)
                  when "court_id" then t.(:edit_field_label_court)
                  else field
                  end

                message_id = cb.message_id
                state = { game_id: game_id, field: field, step: "field", msg_id: message_id, chat_id: cb.chat_id.to_s }
                Rails.cache.write("telegram:edit:chat:#{cb.chat_id}", state, expires_in: 30.minutes)
                Rails.cache.write("telegram:edit:msg:#{message_id}", state, expires_in: 30.minutes) if message_id

                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil

                if field == "sport"
                  require "cgi"
                  buttons = User::SPORTS.each_slice(2).map do |row|
                    row.map { |s| { text: s, callback_data: "game:edit:set:sport:#{game_id}:#{CGI.escape(s)}:#{message_id}" } }
                  end
                  buttons << [ { text: t.(:cancel_btn), callback_data: "game:edit:cancel:#{game_id}:#{message_id}" } ]
                  send_or_edit_with_buttons(cb.chat_id, t.(:edit_choose_new_sport), buttons, message_id: message_id)
                elsif field == "players_count"
                  buttons = [
                    [ { text: "2", callback_data: "game:edit:set:players_count:#{game_id}:2:#{message_id}" } ],
                    [ { text: "4", callback_data: "game:edit:set:players_count:#{game_id}:4:#{message_id}" } ],
                    [ { text: t.(:cancel_btn), callback_data: "game:edit:cancel:#{game_id}:#{message_id}" } ]
                  ]
                  send_or_edit_with_buttons(cb.chat_id, t.(:edit_choose_players_count), buttons, message_id: message_id)
                elsif field == "court_id"
                  page = 1
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                  callback_page = { "data" => "game:edit:court:page:#{game_id}:#{page}:#{message_id}", "from" => callback["from"], "message" => callback["message"] }
                  handle_callback(callback_page) rescue nil
                else
                  send_or_edit_with_buttons(
                    cb.chat_id,
                    t.(:edit_send_new_value_for, label: label),
                    [[ { text: t.(:cancel_btn), callback_data: "game:edit:cancel:#{game_id}:#{message_id}" } ]],
                    message_id: message_id
                  )
                end
                nil

              when /\Agame:edit:show:(\d+):(\d+)\z/
                game_id = $1.to_i
                msg_id = $2.to_i
                game = Game.find_by(id: game_id)
                user = Telegram::Helpers::UserLookup.find_user(cb.chat_id)
                unless game && user && (user.admin? || user.id == game.user_id)
                  poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id, text: t.(:unauthorized_or_not_found), show_alert: true }) rescue nil
                  return
                end
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                Telegram::Flows::Games::EditPrompter.send_edit_prompts(cb.chat_id, game.id, msg_id) rescue nil
                nil

              when /\Agame:edit:cancel:(\d+):(\d+)\z/
                Telegram::Flows::Games::EditResponder.handle_cancel(callback) rescue nil
                nil

              when /\Agame:edit:confirm:(\d+)\z/
                gid = $1.to_i
                poller.send_api("answerCallbackQuery", { callback_query_id: cb.cb_id }) rescue nil
                Telegram::Handlers::GamesHandler.show_game(cb.chat_id, gid, 1, message_id: cb.message_id) rescue nil
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
