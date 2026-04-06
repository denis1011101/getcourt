module Telegram
  module Handlers
    class FindCoachHandler
      PER_PAGE = 5

      class << self
        include Telegram::Handlers::ReplyHelpers

        def list_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          page = page.to_i < 1 ? 1 : page.to_i
          favorite_ids = user&.favorite_court_ids || []

          # Find coaches, prioritize overlapping favorite courts, then same city
          scope = User.where(coach: true).includes(:favorite_courts)
          user_city = user&.city_name.to_s.strip.downcase.presence

          coaches = scope.to_a.sort_by do |coach|
            overlap_count = favorite_ids.any? ? (coach.favorite_courts.map(&:id) & favorite_ids).size : 0
            same_city = user_city && coach.city_name.to_s.strip.downcase == user_city ? 0 : 1
            [ -overlap_count, same_city, coach.name.to_s ]
          end

          total = coaches.size
          pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
          offset = (page - 1) * PER_PAGE
          items = coaches.slice(offset, PER_PAGE) || []

          header = t.(:coaches_page, page: page, pages: pages)

          if items.empty?
            text = "#{header}\n\n#{t.(:no_coaches_found)}"
            buttons = [ [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ] ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
            return
          end

          buttons = items.map do |coach|
            name = Telegram::Helpers::UserLookup.display_name(coach)
            sports = coach.respond_to?(:preferred_sports) && coach.preferred_sports.present? ? Array(coach.preferred_sports).join(", ") : "—"
            city = coach.city_name.to_s.titleize.presence || "—"
            label = "#{name} · #{sports} · #{city}"
            # Truncate label for Telegram button limit (64 chars)
            label = label[0..60] + "..." if label.length > 63
            [ { text: label, callback_data: "coach:show:#{coach.id}" } ]
          end

          nav = []
          nav << [ { text: t.(:prev_page), callback_data: "menu:find_coach:page:#{page - 1}" } ] if page > 1
          nav << [ { text: t.(:next_page), callback_data: "menu:find_coach:page:#{page + 1}" } ] if page < pages
          buttons.concat(nav) unless nav.empty?
          buttons << [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        def show_coach(chat_id, coach_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          coach = User.find_by(id: coach_id, coach: true)
          unless coach
            send_or_edit_text(chat_id, t.(:user_not_found), message_id: message_id)
            return
          end

          name = Telegram::Helpers::UserLookup.display_name(coach)
          sports = coach.respond_to?(:preferred_sports) && coach.preferred_sports.present? ? Array(coach.preferred_sports).join(", ") : "—"
          city = coach.city_name.to_s.titleize.presence || "—"
          host = ENV.fetch("APP_HOST", "https://getcourt.co")
          courts = if coach.court_preferences_note.present?
            coach.court_preferences_note
          elsif coach.favorite_courts.any?
            coach.favorite_courts.map do |court|
              court_url = Rails.application.routes.url_helpers.court_url(court, host: host)
              "[#{court.name}](#{court_url})"
            end.join(", ")
          else
            "—"
          end

          text = t.(:coach_card, name: name, sports: sports, city: city, courts: courts)
          if coach.about_me.present?
            text = "#{text}\n#{t.(:about_me_label, value: coach.about_me)}"
          end

          buttons = [
            [ { text: t.(:back), callback_data: "menu:find_coach:page:1" } ],
            [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]
          ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end
      end
    end
  end
end
