module Telegram
  module Handlers
    class SurveyHandler
      Conversation = Telegram::Helpers::Conversation

      class << self
        # Entry from /start
        def start(chat_id, user = nil)
          locale = user ? Telegram::I18n.locale_for(user) : Telegram::I18n::DEFAULT_LOCALE
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          Telegram::Api.send_simple(chat_id, t.(:greeting))
          Conversation.start(chat_id)
          send_language_picker(chat_id, locale: locale)
        end

        # Handle plain text messages (e.g. force-reply for city)
        def handle_message(chat_id, text, user = nil)
          conv_locale = Conversation.get(chat_id)["language"].to_s
          locale = if Telegram::I18n::LOCALES.include?(conv_locale)
            conv_locale
          elsif user
            Telegram::I18n.locale_for(user)
          else
            Telegram::I18n::DEFAULT_LOCALE
          end
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          state = Conversation.get(chat_id)
          step = state["step"].to_s

          case step
          when "ask_city"
            if text.to_s.strip.empty?
              Telegram::Api.send_force_reply(chat_id, t.(:ask_city))
              return
            end

            txt = text.to_s.strip
            if txt.downcase == "skip"
              Conversation.set_city(chat_id, nil)
            else
              Conversation.set_city(chat_id, txt)
            end

            Conversation.set_step(chat_id, "ask_sports")
            send_sports_picker(chat_id, locale: locale)
          else
            Telegram::Api.send_simple(chat_id, t.(:please_use_buttons))
          end
        end

        # Handle inline callback queries
        def handle_callback(callback)
          data = (callback["data"] || "").to_s
          cb_id = callback["id"]
          from = callback["from"] || {}
          chat_id = (callback.dig("message", "chat", "id") || from["id"]).to_s
          user = find_user_by_chat(chat_id)

          # Use language from conversation state if already chosen, else fall back to user/default
          conv_locale = Conversation.get(chat_id)["language"].to_s
          locale = if Telegram::I18n::LOCALES.include?(conv_locale)
            conv_locale
          elsif user
            Telegram::I18n.locale_for(user)
          else
            Telegram::I18n::DEFAULT_LOCALE
          end
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          case
          when data.start_with?("survey_lang:set:")
            lang = data.split(":", 3).last
            Conversation.update(chat_id, "language" => lang)
            Conversation.set_step(chat_id, "ask_city")
            Telegram::Api.answer_callback(cb_id)
            city_locale = Telegram::I18n::LOCALES.include?(lang) ? lang : locale
            Telegram::Api.send_force_reply(chat_id, Telegram::I18n.t(:ask_city, locale: city_locale))
          when data == "survey_lang:skip"
            Conversation.set_step(chat_id, "ask_city")
            Telegram::Api.answer_callback(cb_id)
            Telegram::Api.send_force_reply(chat_id, t.(:ask_city))
          when data.start_with?("sport:toggle:")
            sport = data.split(":", 3).last
            Conversation.toggle_sport(chat_id, sport)
            send_sports_picker(chat_id, answer: cb_id, locale: locale)
          when data == "sport:done"
            Conversation.set_step(chat_id, "ask_skill")
            selected = Conversation.get(chat_id)["selected_sports"] || []
            if selected.empty?
              Telegram::Api.answer_callback(cb_id, t.(:select_at_least_one), show_alert: true)
              send_sports_picker(chat_id, locale: locale)
              return
            end
            Conversation.update(chat_id, "skill_queue" => selected.dup)
            Telegram::Api.answer_callback(cb_id)
            ask_next_skill(chat_id, locale: locale)
          when data == "sport:skip_all"
            Conversation.update(chat_id, "selected_sports" => [], "skill_queue" => [])
            Conversation.set_step(chat_id, "ask_coach")
            Telegram::Api.answer_callback(cb_id)
            send_coach_picker(chat_id, locale: locale)
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
              ask_next_skill(chat_id, locale: locale)
            else
              Conversation.set_step(chat_id, "ask_coach")
              send_coach_picker(chat_id, locale: locale)
            end
          when data.start_with?("skill:skip:")
            queue = (Conversation.get(chat_id)["skill_queue"] || [])
            queue.shift
            Conversation.update(chat_id, "skill_queue" => queue)
            Telegram::Api.answer_callback(cb_id)
            if queue.any?
              ask_next_skill(chat_id, locale: locale)
            else
              Conversation.set_step(chat_id, "ask_coach")
              send_coach_picker(chat_id, locale: locale)
            end
          when data.start_with?("coach:set:")
            val = data.split(":", 3).last
            Conversation.update(chat_id, "coach" => (val == "yes"))
            Conversation.set_step(chat_id, "ask_notifications")
            Telegram::Api.answer_callback(cb_id)
            send_notifications_picker(chat_id, locale: locale)
          when data == "coach:skip"
            Conversation.update(chat_id, "coach" => nil)
            Conversation.set_step(chat_id, "ask_notifications")
            Telegram::Api.answer_callback(cb_id)
            send_notifications_picker(chat_id, locale: locale)
          when data.start_with?("notifications:set:")
            val = data.split(":", 2).last
            Conversation.set_notifications(chat_id, val == "yes")
            Telegram::Api.answer_callback(cb_id)
            finish_survey(chat_id, user, t)
          when data == "notifications:skip"
            Conversation.set_notifications(chat_id, nil)
            Telegram::Api.answer_callback(cb_id)
            finish_survey(chat_id, user, t)
          else
            Telegram::Api.answer_callback(cb_id, t.(:unknown_action), show_alert: false)
          end
        rescue => e
          Rails.logger.error "[Telegram::Handlers::SurveyHandler] callback error: #{e.class} #{e.message}"
        end

        private

        def finish_survey(chat_id, user, t)
          if user
            Telegram::Helpers::UserProfile.persist_from_conversation(chat_id, user, finish: true)
            user.update(onboarded_at: Time.current)
          else
            Conversation.finish(chat_id)
          end
          Telegram::Api.send_simple(chat_id, t.(:survey_completion))
          Telegram::Handlers::MenuHandler.menu(chat_id)
        end

        def send_language_picker(chat_id, locale: "ru")
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          buttons = [
            [ { text: "Русский 🇷🇺", callback_data: "survey_lang:set:ru" } ],
            [ { text: "English 🇬🇧",  callback_data: "survey_lang:set:en" } ],
            [ { text: t.(:skip),      callback_data: "survey_lang:skip" } ]
          ]
          Telegram::Api.send_with_buttons(chat_id, t.(:ask_language), buttons)
        end

        def send_sports_picker(chat_id, answer: nil, locale: "ru")
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          state = Conversation.get(chat_id)
          selected = (state["selected_sports"] || []).map(&:to_s)
          buttons = sports_list.map do |label, key|
            checked = selected.include?(key) ? " ✓" : ""
            [ { text: "#{label}#{checked}", callback_data: "sport:toggle:#{key}" } ]
          end
          buttons << [ { text: t.(:done), callback_data: "sport:done" } ]
          buttons << [ { text: t.(:skip), callback_data: "sport:skip_all" } ]
          Telegram::Api.send_with_buttons(chat_id, t.(:ask_sports), buttons)
          Telegram::Api.answer_callback(answer) if answer
        end

        def ask_next_skill(chat_id, locale: "ru")
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          queue = (Conversation.get(chat_id)["skill_queue"] || [])
          sport = queue.first
          sport_label = sports_list.find { |l, k| k == sport }&.first || sport.to_s.humanize
          buttons = skill_levels_list.map { |label, key| [ { text: label, callback_data: "skill:set:#{sport}:#{key}" } ] }
          buttons << [ { text: t.(:skip), callback_data: "skill:skip:#{sport}" } ]
          Telegram::Api.send_with_buttons(chat_id, t.(:ask_skill, sport: sport_label), buttons)
        end

        def send_coach_picker(chat_id, locale: "ru")
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          buttons = [
            [ { text: t.(:yes_label), callback_data: "coach:set:yes" } ],
            [ { text: t.(:no_label),  callback_data: "coach:set:no" } ],
            [ { text: t.(:skip),      callback_data: "coach:skip" } ]
          ]
          Telegram::Api.send_with_buttons(chat_id, t.(:ask_coach), buttons)
        end

        def send_notifications_picker(chat_id, locale: "ru")
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
          buttons = [
            [ { text: t.(:yes_label), callback_data: "notifications:set:yes" } ],
            [ { text: t.(:no_label),  callback_data: "notifications:set:no" } ],
            [ { text: t.(:skip),      callback_data: "notifications:skip" } ]
          ]
          Telegram::Api.send_with_buttons(chat_id, t.(:ask_notifications), buttons)
        end

        def sports_list
          User::SPORTS.map do |label|
            key = label.to_s.downcase.gsub(/\s+/, "_")
            [ label, key ]
          end
        end

        def skill_levels_list
          User::SKILL_LEVELS.map { |lvl| [ lvl.to_s.titleize, lvl.to_s ] }
        end

        def find_user_by_chat(chat_id)
          User.find_by(telegram_chat_id: chat_id) rescue nil
        end
      end
    end
  end
end
