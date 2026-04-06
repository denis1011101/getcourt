module Telegram
  module Flows
    module Profile
      module FavoriteCourtsFlow
        module_function

        PER_PAGE = 5

        def process_favorite_courts_callback(chat_id, action, arg = nil, cb_id: nil, message_id: nil)
          key = "tg:conv:#{chat_id}"
          conv = Rails.cache.read(key) || {}
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(local_key, **args) { Telegram::I18n.t(local_key, locale: locale, **args) }

          unless user
            Telegram::Api.answer_callback(cb_id, t.(:no_linked_account), show_alert: false) rescue nil
            return
          end

          selections = Array(conv["selections"]).map(&:to_i)
          page = conv["page"].to_i
          page = 1 if page < 1

          case action
          when "toggle"
            court_id = arg.to_i
            visible_ids = visible_courts_for(user).map(&:id)
            return unless visible_ids.include?(court_id)

            if selections.include?(court_id)
              selections.delete(court_id)
            else
              selections << court_id
            end

            conv["flow"] = "profile_favorite_courts"
            conv["selections"] = selections
            conv["page"] = page
            Rails.cache.write(key, conv, expires_in: 2.hours)
            render_menu(chat_id, selections, page, message_id, cb_id, user: user)
          when "page"
            new_page = arg.to_i
            new_page = 1 if new_page < 1
            conv["flow"] = "profile_favorite_courts"
            conv["selections"] = selections
            conv["page"] = new_page
            Rails.cache.write(key, conv, expires_in: 2.hours)
            render_menu(chat_id, selections, new_page, message_id, cb_id, user: user)
          when "save"
            user.transaction do
              user.favorite_court_ids = selections
              user.update!(court_preferences_note: nil)
            end

            if user.persisted?
              Rails.cache.delete(key) rescue nil
              Telegram::Flows::ProfileFlow.start_edit_profile(chat_id, message_id: message_id)
              Telegram::Api.answer_callback(cb_id, t.(:favorite_courts_saved)) rescue nil
            end
          when "cancel"
            Rails.cache.delete(key) rescue nil
            Telegram::Flows::ProfileFlow.start_edit_profile(chat_id, message_id: message_id)
            Telegram::Api.answer_callback(cb_id, t.(:edit_cancelled)) rescue nil
          else
            Telegram::Api.answer_callback(cb_id, t.(:unknown_action), show_alert: false) rescue nil
          end
        rescue => e
          if action == "save"
            Telegram::Api.answer_callback(cb_id, t.(:favorite_courts_save_failed), show_alert: true) rescue nil
          end
          Rails.logger.error "[Telegram::Flows::Profile::FavoriteCourtsFlow] exception: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        end

        def render_menu(chat_id, selections, page, message_id, cb_id, user: nil)
          user ||= Telegram::Helpers::UserLookup.find_user(chat_id)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(local_key, **args) { Telegram::I18n.t(local_key, locale: locale, **args) }
          courts = visible_courts_for(user)
          pages = [ (courts.size.to_f / PER_PAGE).ceil, 1 ].max
          page = 1 if page.to_i < 1
          page = pages if page.to_i > pages
          offset = (page - 1) * PER_PAGE
          current_courts = courts.slice(offset, PER_PAGE) || []

          buttons = current_courts.map do |court|
            label = selections.include?(court.id) ? "✓ #{court.name}" : court.name
            [ { text: label, callback_data: "profile:favorite_courts:toggle:#{court.id}" } ]
          end

          nav = []
          nav << { text: t.(:prev_page), callback_data: "profile:favorite_courts:page:#{page - 1}" } if page > 1
          nav << { text: t.(:next_page), callback_data: "profile:favorite_courts:page:#{page + 1}" } if page < pages
          buttons << nav if nav.any?
          buttons << [ { text: t.(:save), callback_data: "profile:favorite_courts:save" }, { text: t.(:back), callback_data: "profile:favorite_courts:cancel" } ]

          selected_names = courts.select { |court| selections.include?(court.id) }.map(&:name)
          current = selected_names.any? ? selected_names.join(", ") : t.(:favorite_courts_empty)
          text = "#{t.(:favorite_courts_prompt)}\n#{current}\n\n#{t.(:coaches_page, page: page, pages: pages)}"

          if message_id
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons) rescue nil
            Telegram::Api.answer_callback(cb_id) rescue nil
          end
        end

        def visible_courts_for(user)
          courts = Court.visible_to(user).to_a
          user_city = user&.city_name.to_s.strip.downcase.presence
          return courts unless user_city

          local, other = courts.partition { |court| court.city_name.to_s.strip.downcase == user_city }
          local + other
        end
      end
    end
  end
end
