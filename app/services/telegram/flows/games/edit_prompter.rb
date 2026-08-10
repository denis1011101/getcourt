module Telegram
  module Flows
    module Games
      class EditPrompter
        class << self
          # Delegate class call to instance so ManageFlow can call .handle_callback
          def handle_callback(callback)
            new.handle_callback(callback)
          end

          # Build unified buttons for :create and :edit flows
          def build_buttons(mode, game_id, message_id = nil)
            case mode
            when :create
              [
                [ { text: "Date", callback_data: "game:create:field:date:#{game_id}" } ],
                [ { text: "Time", callback_data: "game:create:field:time:#{game_id}" } ],
                [ { text: "Players", callback_data: "game:create:field:players_count:#{game_id}" } ],
                [ { text: "Sport / Title", callback_data: "game:create:field:sport:#{game_id}" } ],
                [ { text: "Court (prefilled)", callback_data: "game:create:field:court_id:#{game_id}" } ],
                [ { text: "Comment", callback_data: "game:create:field:comment:#{game_id}" } ],
                [ { text: "Preview / Confirm", callback_data: "game:create:confirm:#{game_id}" } ],
                # include original message_id when present so cancel can restore previous view
                [ { text: "Cancel (delete draft)", callback_data: "game:create:cancel:#{game_id}" + (message_id ? ":#{message_id}" : "") } ]
              ]
            when :edit
              # mirror create layout for edit mode (use edit callbacks)
              kb = [
                [ { text: "Date", callback_data: "game:edit:field:#{game_id}:date" } ],
                [ { text: "Time", callback_data: "game:edit:field:#{game_id}:time" } ],
                [ { text: "Players", callback_data: "game:edit:field:#{game_id}:players_count" } ],
                [ { text: "Sport / Title", callback_data: "game:edit:field:#{game_id}:sport" } ],
                [ { text: "Court", callback_data: "game:edit:field:#{game_id}:court_id" } ],
                [ { text: "Comment", callback_data: "game:edit:field:#{game_id}:comment" } ],
                [ { text: "Preview / Confirm", callback_data: "game:edit:confirm:#{game_id}" } ]
              ]
              cb = "game:edit:cancel:#{game_id}"
              cb += ":#{message_id}" if message_id
              kb << [ { text: "Cancel", callback_data: cb } ]
              kb
            else
              []
            end
          end

          def prompt_text(mode, game_id = nil)
            mode == :create ? "CREATE GAME — use buttons below to fill fields. Click a field to enter value. When ready — press Preview / Confirm." : "Edit game ##{game_id} — choose field to edit:"
          end

          def send_edit_prompts(chat_id, game_id, original_message_id = nil)
            poller = Telegram::Poller.new
            chat_id = chat_id.to_s
            state = nil
            # use unified prompt text + buttons for edit mode
            initial = prompt_text(:edit, game_id)
            kb = build_buttons(:edit, game_id, original_message_id)

            if original_message_id
              resp = poller.send_api("editMessageText", {
                chat_id: chat_id,
                message_id: original_message_id,
                text: initial,
                reply_markup: { inline_keyboard: kb }
              }) rescue nil
              # treat Telegram "message is not modified" as success and keep original_message_id
              if resp.nil? || (resp.is_a?(Hash) && resp["ok"] == true) || (resp.is_a?(Hash) && resp["ok"] == false && resp["description"] =~ /not modified/i)
                msg_id = original_message_id
              else
                msg_id = nil
              end
            else
              resp = poller.send_api("sendMessage", {
                chat_id: chat_id,
                text: initial,
                 reply_markup: { inline_keyboard: kb }
               }) rescue nil
               msg_id = resp.dig("result", "message_id") rescue nil
            end

            if msg_id
              state = { game_id: game_id, step: 1, chat_id: chat_id, msg_id: msg_id }
              Rails.cache.write("telegram:edit:chat:#{chat_id}", state, expires_in: 30.minutes)
              Rails.cache.write("telegram:edit:msg:#{msg_id}", state, expires_in: 30.minutes)
              Rails.logger.info "[EditPrompter] stored cache for chat #{chat_id}: #{state.inspect}"
            else
              Rails.logger.error "[EditPrompter] failed to create/edit prompt for chat #{chat_id}"
            end

            state
          end
        end

        # Instance handler for create/edit field callbacks delegated from ManageFlow
        def handle_callback(callback)
          data = (callback["data"] || "").to_s
          cb_id = callback["id"]
          from = callback["from"] || {}
          chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
          message_id = callback.dig("message", "message_id") || callback["inline_message_id"]
          poller = Telegram::Poller.new

          # support both create and edit field callbacks
          if data =~ /\Agame:create:field:(\w+):(\d+)\z/ || data =~ /\Agame:edit:field:(\d+):([a-z_]+)\z/
            if data =~ /\Agame:create:field:(\w+):(\d+)\z/
              field = $1.to_s
              game_id = $2.to_i
            else
              game_id = $1.to_i
              field = $2.to_s
            end

            label =
              case field
              when "date" then "date (YYYY-MM-DD)"
              when "time" then "time (HH:MM)"
              when "players_count" then "players count (integer)"
              when "sport" then "sport"
              when "court_id" then "court id (integer)"
              when "comment" then "comment (up to 500 characters)"
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
                poller.send_api("editMessageText", { chat_id: chat_id, message_id: message_id, text: "Choose new sport:", reply_markup: { inline_keyboard: buttons } }) rescue nil
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
                poller.send_api("editMessageText", { chat_id: chat_id, message_id: message_id, text: "Choose players count:", reply_markup: { inline_keyboard: buttons } }) rescue nil
              else
                poller.send_api("sendMessage", { chat_id: chat_id, text: "Choose players count:", reply_markup: { inline_keyboard: buttons } }) rescue nil
              end

            elsif field == "court_id"
              page = 1
              callback_page = { "data" => "game:edit:court:page:#{game_id}:#{page}:#{message_id}", "from" => callback["from"], "message" => callback["message"] }
              Telegram::Flows::Games::ManageFlow.handle_callback(callback_page) rescue nil

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
          end
        end
      end
    end
  end
end
