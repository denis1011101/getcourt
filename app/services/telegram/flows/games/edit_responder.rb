module Telegram
  module Flows
    module Games
      class EditResponder
        class << self
          # Handle ordinary user messages (not reply-to). Call from your message processor.
          def handle_message(message)
            chat_id = (message.dig("chat","id") || message.dig("from","id")).to_s
            state = Rails.cache.read("telegram:edit:chat:#{chat_id}")
            Rails.logger.info "[EditResponder] handle_message chat_id=#{chat_id} state=#{state.inspect}"
            begin
              return unless state
            rescue => e
              Rails.logger.error "[EditResponder] read state error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
              return
            end

            msg_id = state[:msg_id]
            game_id = state[:game_id]
            poller = Telegram::Poller.new
            text = message["text"].to_s.strip

            case state[:step]
            when 1
              begin
                d = Date.parse(text)
                Rails.logger.info "[EditResponder] parsed date=#{d} from text=#{text.inspect}"
              rescue
                Rails.logger.warn "[EditResponder] invalid date format: #{text.inspect}"
                poller.send_api("sendMessage", { chat_id: chat_id, text: "Invalid date format. Please send date as YYYY-MM-DD (Question 1/3)." }) rescue nil
                return
              end

              # delete user's message, confirm received and edit bot prompt to next question
              begin
                poller.send_api("deleteMessage", { chat_id: chat_id, message_id: message["message_id"] }) rescue nil
              rescue => _e; end

              next_text = "Date recorded: #{d}\nQuestion 2/3 — Send the TIME (HH:MM):"
              poller.send_api("editMessageText", {
                chat_id: chat_id,
                message_id: msg_id,
                text: next_text,
                reply_markup: { inline_keyboard: [[{ text: "Cancel", callback_data: "game:edit:cancel:#{game_id}:#{msg_id}" }]] }
              }) rescue nil

              written = Rails.cache.write("telegram:edit:chat:#{chat_id}", state.merge(step: 2, date: d), expires_in: 30.minutes)
              Rails.logger.info "[EditResponder] cache write for telegram:edit:chat:#{chat_id} returned=#{written.inspect}"

            when 2
              unless text =~ /\A\d{1,2}:\d{2}\z/
                poller.send_api("sendMessage", { chat_id: chat_id, text: "Invalid time format. Please send time as HH:MM (Question 2/3)." }) rescue nil
                return
              end

              # delete user's message, confirm and prompt final input
              begin
                poller.send_api("deleteMessage", { chat_id: chat_id, message_id: message["message_id"] }) rescue nil
              rescue => _e; end

              next_text = "Time recorded: #{text}\nQuestion 3/3 — Finally send: players count sport (e.g. 2 or 4)"
              poller.send_api("editMessageText", {
                chat_id: chat_id,
                message_id: msg_id,
                text: next_text,
                reply_markup: { inline_keyboard: [[{ text: "Cancel", callback_data: "game:edit:cancel:#{game_id}:#{msg_id}" }]] }
              }) rescue nil

              Rails.cache.write("telegram:edit:chat:#{chat_id}", state.merge(step: 3, time: text), expires_in: 30.minutes)

           when 3
              parts = text.split
              players = parts[0].to_i rescue 0
              sport = parts[1]
              court_id = parts[2]

              game = Game.find_by(id: game_id)
              if game
                attrs = {}
                attrs[:date] = (state[:date].strftime("%Y-%m-%d") rescue nil) if state[:date]
                attrs[:time] = state[:time]
                attrs[:players_count] = players if players > 0
                attrs[:sport] = sport if sport.present?
                attrs[:court_id] = court_id.to_i if court_id.present?
                begin
                  game.update(attrs.compact)
                  # delete user's final message and confirm saved values in bot message
                  begin
                    poller.send_api("deleteMessage", { chat_id: chat_id, message_id: message["message_id"] }) rescue nil
                  rescue => _e; end

                  summary = []
                  summary << "Date: #{attrs[:date]}" if attrs[:date]
                  summary << "Time: #{attrs[:time]}" if attrs[:time]
                  summary << "Players: #{attrs[:players_count]}" if attrs[:players_count]
                  summary << "Sport: #{attrs[:sport]}" if attrs[:sport]
                  summary << "Court: #{attrs[:court_id]}" if attrs[:court_id]
                  poller.send_api("editMessageText", { chat_id: chat_id, message_id: msg_id, text: "Edit saved:\n" + summary.join(", ") }) rescue nil
                rescue => e
                  poller.send_api("editMessageText", { chat_id: chat_id, message_id: msg_id, text: "Failed to update: #{e.message}" }) rescue nil
                end
              else
                poller.send_api("editMessageText", { chat_id: chat_id, message_id: msg_id, text: "Game not found." }) rescue nil
              end

              Rails.cache.delete("telegram:edit:chat:#{chat_id}")

            when "field"
              field = state[:field].to_s
              game = Game.find_by(id: state[:game_id])
              unless game
                poller.send_api("sendMessage", { chat_id: chat_id, text: "Game not found." }) rescue nil
                Rails.cache.delete("telegram:edit:chat:#{chat_id}")
                return
              end

              attrs = {}
              begin
                case field
                when "date"
                  d = Date.parse(text) rescue nil
                  unless d
                    poller.send_api("sendMessage", { chat_id: chat_id, text: "Invalid date. Use YYYY-MM-DD." }) rescue nil
                    return
                  end
                  attrs[:date] = d
                when "time"
                  unless text =~ /\A\d{1,2}:\d{2}\z/
                    poller.send_api("sendMessage", { chat_id: chat_id, text: "Invalid time. Use HH:MM." }) rescue nil
                    return
                  end
                  attrs[:time] = text
                when "players_count"
                  unless text =~ /\A\d+\z/
                    poller.send_api("sendMessage", { chat_id: chat_id, text: "Invalid number. Send integer." }) rescue nil
                    return
                  end
                  attrs[:players_count] = text.to_i
                when "sport"
                  attrs[:sport] = text.presence
                when "court_id"
                  unless text =~ /\A\d+\z/
                    poller.send_api("sendMessage", { chat_id: chat_id, text: "Invalid court id. Send integer." }) rescue nil
                    return
                  end
                  attrs[:court_id] = text.to_i
                else
                  poller.send_api("sendMessage", { chat_id: chat_id, text: "Unknown field." }) rescue nil
                  Rails.cache.delete("telegram:edit:chat:#{chat_id}")
                  return
                end
              rescue => _e
                poller.send_api("sendMessage", { chat_id: chat_id, text: "Invalid value." }) rescue nil
                return
              end
              begin
                game.update(attrs.compact)
                poller.send_api("deleteMessage", { chat_id: chat_id, message_id: message["message_id"] }) rescue nil
                msg_id = state[:msg_id]
                Telegram::Flows::Games::EditPrompter.send_edit_prompts(chat_id, game.id, msg_id) rescue nil
                Rails.cache.write("telegram:edit:chat:#{chat_id}", state.merge(step: "field"), expires_in: 30.minutes)
              rescue => e
                poller.send_api("sendMessage", { chat_id: chat_id, text: "Failed to update: #{e.message}" }) rescue nil
                Rails.cache.delete("telegram:edit:chat:#{chat_id}")
              end
            end
          end

          def handle_cancel(callback)
            cb_id = callback["id"]
            data = (callback["data"] || "").to_s
            chat_id = (callback.dig("message","chat","id") || callback["from"] && callback["from"]["id"]).to_s
            message_id = callback.dig("message","message_id")
            # clear both chat and message keyed state
            Rails.cache.delete("telegram:edit:chat:#{chat_id}")
            Rails.cache.delete("telegram:edit:msg:#{message_id}")

            if data =~ /\Agame:edit:cancel:(\d+):(\d+)\z/
              game_id = $1.to_i
              # try to restore original game card; fallback to simple text if it fails
              begin
                Telegram::Handlers::GamesHandler.show_game(chat_id, game_id, 1, message_id: message_id)
              rescue => _
                Telegram::Api.edit_message_text(chat_id, message_id, "Edit cancelled.") rescue nil
              end
            else
              Telegram::Api.edit_message_text(chat_id, message_id, "Edit cancelled.") rescue nil
            end

            Telegram::Poller.new.send_api("answerCallbackQuery", { callback_query_id: cb_id }) rescue nil
          end
        end
      end
    end
  end
end
