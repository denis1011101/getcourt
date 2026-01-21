module Telegram
  module Flows
    module Profile
      module SportsFlow
        module_function

        SKILL_LEVELS = User::SKILL_LEVELS rescue %w[beginner intermediate advanced pro]

        def process_sports_callback(chat_id, action, arg = nil, cb_id: nil, message_id: nil)
          key = "tg:conv:#{chat_id}"
          conv = Rails.cache.read(key) || {}

          case action
          when "toggle"
            return unless arg
            selections = Array(conv["selections"])
            if selections.include?(arg)
              selections.delete(arg)
            else
              selections << arg
            end
            conv["flow"] = "profile_sports"
            conv["selections"] = selections
            Rails.cache.write(key, conv, expires_in: 2.hours)
            render_sports_menu(chat_id, selections, message_id, cb_id)
          when "save"
            # move to levels selection step
            selections = Array(conv["selections"])
            conv["flow"] = "profile_sports_levels"
            conv["levels"] = conv["levels"] || {}
            # prefill levels from user if present
            user = User.find_by(telegram_chat_id: chat_id.to_s)
            if user && user.skill_levels.present?
              conv["levels"].merge!(user.skill_levels.slice(*selections))
            end
            Rails.cache.write(key, conv, expires_in: 2.hours)
            render_levels_overview(chat_id, conv["selections"], conv["levels"], message_id, cb_id)
          when "cancel"
            Rails.cache.delete(key) rescue nil
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, "Edit cancelled.", [[{ text: "Edit profile", callback_data: "profile:edit" }]]) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          when "level"
            sport = arg
            return Telegram::Api.answer_callback(cb_id, text: "No sport specified", show_alert: false) unless sport
            render_level_options(chat_id, sport, message_id, cb_id)
          when "level_set"
            # arg encoded as "sport|level" where level may be empty for none
            sport, level = (arg || "").split("|", 2)
            levels = conv["levels"] || {}
            levels[sport] = level.presence
            conv["levels"] = levels
            Rails.cache.write(key, conv, expires_in: 2.hours)
            render_levels_overview(chat_id, conv["selections"] || [], conv["levels"], message_id, cb_id)
          when "save_levels"
            selections = Array(conv["selections"])
            levels = conv["levels"] || {}
            user = User.find_by(telegram_chat_id: chat_id.to_s)
            unless user
              Rails.cache.delete(key) rescue nil
              return Telegram::Api.answer_callback(cb_id, text: "No linked account", show_alert: false) rescue nil
            end

            # persist preferred_sports and skill_levels atomically
            user.preferred_sports = selections if user.respond_to?(:preferred_sports=)
            user.skill_levels = (levels || {})
            if user.save
              Rails.cache.delete(key) rescue nil
              Telegram::Api.edit_message_with_buttons(chat_id, message_id, "*Edit profile*\nSports saved: #{selections.any? ? selections.join(', ') : '—'}", [[{ text: "Edit profile", callback_data: "profile:edit" }]]) rescue nil
              Telegram::Api.answer_callback(cb_id) rescue nil
            else
              Rails.logger.error "[Telegram::Flows::Profile::SportsFlow] failed saving sports for user=#{user.id} errors=#{user.errors.full_messages.join(', ')}"
              Telegram::Api.answer_callback(cb_id, text: "Failed to save sports: #{user.errors.full_messages.join(', ')}", show_alert: true) rescue nil
            end
          else
            Telegram::Api.answer_callback(cb_id, text: "Unknown action", show_alert: false) rescue nil
          end
        rescue => e
          Rails.logger.error "[Telegram::Flows::Profile::SportsFlow] exception: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        end

        # render current sports selection with "Set level" buttons
        def render_levels_overview(chat_id, selections, levels, message_id, cb_id)
          buttons = selections.map do |s|
            label = "#{s}#{levels[s].present? ? " (#{levels[s].titleize})" : ""}"
            [{ text: label, callback_data: "profile:sports:level:#{CGI.escape(s)}" }]
          end
          buttons << [{ text: "Save", callback_data: "profile:sports:save_levels" }, { text: "Back", callback_data: "profile:sports:cancel" }]
          text = "Set levels for selected sports:\n#{selections.any? ? selections.map { |s| "- #{s}#{levels[s].present? ? " (#{levels[s].titleize})" : ''}" }.join("\n") : '—'}"
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end

        # render skill level options for one sport
        def render_level_options(chat_id, sport, message_id, cb_id)
          buttons = SKILL_LEVELS.map do |lvl|
            [{ text: lvl.titleize, callback_data: "profile:sports:level_set:#{CGI.escape("#{sport}|#{lvl}")}" }]
          end
          # option to clear
          buttons << [{ text: "None", callback_data: "profile:sports:level_set:#{CGI.escape("#{sport}|")}" }]
          buttons << [{ text: "Back", callback_data: "profile:sports:save_levels" }]
          text = "Select level for #{sport}:"
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end

        # render simple sports checkbox menu (existing)
        def render_sports_menu(chat_id, selections, message_id, cb_id)
          buttons = User::SPORTS.map do |s|
            label = selections.include?(s) ? "✓ #{s}" : s
            [{ text: label, callback_data: "profile:sports:toggle:#{CGI.escape(s)}" }]
          end
          buttons << [{ text: "Save", callback_data: "profile:sports:save" }, { text: "Back", callback_data: "profile:sports:cancel" }]
          text = "Select sports (multiple):\nCurrent: #{selections.any? ? selections.join(', ') : '—'}"
          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end
      end
    end
  end
end
