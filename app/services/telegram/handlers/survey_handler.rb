module Telegram
  module Handlers
    class SurveyHandler
      # SPORTS and SKILL_LEVELS are derived from app/models/user.rb
      # Methods below produce the same [[label, key], ...] shape previously hardcoded.

      GREETING = "Welcome to GetCourt! I will help set up your profile to find opponents."
      ASK_CITY = "Which city are you located in? Please type the city name (or type 'skip')."
      ASK_SPORTS = "Which sports do you play? Select all that apply (tap to toggle), then press Done (or press 'Skip')."
      ASK_SKILL = ->(sport_name) { "What is your skill level in #{sport_name}? Choose one (or press 'Skip'):" }
      ASK_NOTIFICATIONS = "Do you want to enable notifications when opponents are searched in your city? (or press 'Skip')"
      COMPLETION = "Thanks — your preferences have been saved. You will receive notifications if enabled."

      class << self
        # Entry from /start
        def start(chat_id, user = nil)
          # greet
          Telegram::Api.send_simple(chat_id, GREETING)
          # initialize conversation and ask city
          Conversation.start(chat_id)
          Telegram::Api.send_force_reply(chat_id, ASK_CITY)
        end

        # Handle plain text messages (e.g. force-reply for city)
        def handle_message(chat_id, text, user = nil)
          state = Conversation.get(chat_id)
          step = state["step"].to_s

          case step
          when "ask_city"
            if text.to_s.strip.empty?
              Telegram::Api.send_force_reply(chat_id, ASK_CITY)
              return
            end

            txt = text.to_s.strip
            if txt.downcase == "skip"
              Conversation.set_city(chat_id, nil)
            else
              Conversation.set_city(chat_id, txt)
            end

            Conversation.set_step(chat_id, "ask_sports")
            send_sports_picker(chat_id)
          else
            # Not expected here; send fallback
            Telegram::Api.send_simple(chat_id, "Please use the buttons to continue.")
          end
        end

        # Handle inline callback queries
        # callback is the telegram callback_query hash
        def handle_callback(callback)
          data = (callback["data"] || "").to_s
          cb_id = callback["id"]
          from = callback["from"] || {}
          chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
          user = find_user_by_chat(chat_id)

          case
          when data.start_with?("sport:toggle:")
            sport = data.split(":", 3).last
            Conversation.toggle_sport(chat_id, sport)
            # update keyboard to reflect selection
            send_sports_picker(chat_id, answer: cb_id)
          when data == "sport:done"
            Conversation.set_step(chat_id, "ask_skill")
            selected = Conversation.get(chat_id)["selected_sports"] || []
            if selected.empty?
              Telegram::Api.answer_callback(cb_id, "Please select at least one sport.", show_alert: true)
              send_sports_picker(chat_id)
              return
            end
            # queue skills
            Conversation.update(chat_id, "skill_queue" => selected.dup)
            Telegram::Api.answer_callback(cb_id)
            ask_next_skill(chat_id)
          when data == "sport:skip_all"
            Conversation.update(chat_id, "selected_sports" => [], "skill_queue" => [])
            Conversation.set_step(chat_id, "ask_notifications")
            Telegram::Api.answer_callback(cb_id)
            send_notifications_picker(chat_id)
          when data.start_with?("skill:set:")
            parts = data.split(":")
            sport = parts[2]
            level = parts[3]
            Conversation.set_skill(chat_id, sport, level)
            queue = (Conversation.get(chat_id)["skill_queue"] || [])
            queue.shift
            Conversation.update(chat_id, "skill_queue" => queue)
            Telegram::Api.answer_callback(cb_id)
            if queue.any?
              ask_next_skill(chat_id)
            else
              Conversation.set_step(chat_id, "ask_notifications")
              send_notifications_picker(chat_id)
            end
          when data.start_with?("skill:skip:")
            # skip this sport's skill and advance
            queue = (Conversation.get(chat_id)["skill_queue"] || [])
            queue.shift
            Conversation.update(chat_id, "skill_queue" => queue)
            Telegram::Api.answer_callback(cb_id)
            if queue.any?
              ask_next_skill(chat_id)
            else
              Conversation.set_step(chat_id, "ask_notifications")
              send_notifications_picker(chat_id)
            end
          when data.start_with?("notifications:set:")
            val = data.split(":", 2).last
            Conversation.set_notifications(chat_id, val == "yes")
            Telegram::Api.answer_callback(cb_id)
            # persist to user if available
            if user
              Telegram::Helpers::UserProfile.persist_from_conversation(chat_id, user, finish: true)
            else
              # finish conversation anyway
              Conversation.finish(chat_id)
            end
            Telegram::Api.send_simple(chat_id, COMPLETION)
          when data == "notifications:skip"
            Conversation.set_notifications(chat_id, nil)
            Telegram::Api.answer_callback(cb_id)
            if user
              Telegram::Helpers::UserProfile.persist_from_conversation(chat_id, user, finish: true)
            else
              Conversation.finish(chat_id)
            end
            Telegram::Api.send_simple(chat_id, COMPLETION)
          else
            Telegram::Api.answer_callback(cb_id, "Unknown action", show_alert: false)
          end
        rescue => e
          Rails.logger.error "[Telegram::Handlers::SurveyHandler] callback error: #{e.class} #{e.message}"
        end

        private

        def send_sports_picker(chat_id, answer: nil)
          state = Conversation.get(chat_id)
          selected = (state["selected_sports"] || []).map(&:to_s)
          buttons = sports_list.map do |label, key|
            checked = selected.include?(key) ? " ✓" : ""
            [{ text: "#{label}#{checked}", callback_data: "sport:toggle:#{key}" }]
          end
          # add Done button and Skip
          buttons << [{ text: "Done", callback_data: "sport:done" }]
          buttons << [{ text: "Skip", callback_data: "sport:skip_all" }]
          Telegram::Api.send_with_buttons(chat_id, ASK_SPORTS, buttons)
          Telegram::Api.answer_callback(answer) if answer
        end

        def ask_next_skill(chat_id)
          queue = (Conversation.get(chat_id)["skill_queue"] || [])
          sport = queue.first
          sport_label = sports_list.find { |l, k| k == sport }&.first || sport.to_s.humanize
          buttons = skill_levels_list.map { |label, key| [{ text: label, callback_data: "skill:set:#{sport}:#{key}" }] }
          # add Skip for this sport
          buttons << [{ text: "Skip", callback_data: "skill:skip:#{sport}" }]
          Telegram::Api.send_with_buttons(chat_id, ASK_SKILL.call(sport_label), buttons)
        end

        def send_notifications_picker(chat_id)
          buttons = [
            [{ text: "Yes", callback_data: "notifications:set:yes" }],
            [{ text: "No",  callback_data: "notifications:set:no" }],
            [{ text: "Skip", callback_data: "notifications:skip" }]
          ]
          Telegram::Api.send_with_buttons(chat_id, ASK_NOTIFICATIONS, buttons)
        end

        # derive from User model
        def sports_list
          User::SPORTS.map do |label|
            key = label.to_s.downcase.gsub(/\s+/, "_")
            [label, key]
          end
        end

        def skill_levels_list
          User::SKILL_LEVELS.map { |lvl| [lvl.to_s.titleize, lvl.to_s] }
        end

        def find_user_by_chat(chat_id)
          User.find_by(telegram_chat_id: chat_id) rescue nil
        end
      end
    end
  end
end
