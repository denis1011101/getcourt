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

          # Find coaches, prioritize same city
          scope = User.where(coach: true)
          user_city = user&.city_name.to_s.strip.downcase.presence

          if user_city
            # Sort: same city first, then others
            coaches = scope.order(
              Arel.sql("CASE WHEN LOWER(city_name) = #{User.connection.quote(user_city)} THEN 0 ELSE 1 END, name ASC")
            )
          else
            coaches = scope.order(name: :asc)
          end

          total = coaches.count
          pages = [(total.to_f / PER_PAGE).ceil, 1].max
          offset = (page - 1) * PER_PAGE
          items = coaches.offset(offset).limit(PER_PAGE).to_a

          header = t.(:coaches_page, page: page, pages: pages)

          if items.empty?
            text = "#{header}\n\n#{t.(:no_coaches_found)}"
            buttons = [[{ text: t.(:main_menu_btn), callback_data: "menu:main" }]]
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
            [{ text: label, callback_data: "coach:show:#{coach.id}" }]
          end

          nav = []
          nav << [{ text: t.(:prev_page), callback_data: "menu:find_coach:page:#{page - 1}" }] if page > 1
          nav << [{ text: t.(:next_page), callback_data: "menu:find_coach:page:#{page + 1}" }] if page < pages
          buttons.concat(nav) unless nav.empty?
          buttons << [{ text: t.(:main_menu_btn), callback_data: "menu:main" }]

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

          text = t.(:coach_card, name: name, sports: sports, city: city)

          buttons = [
            [{ text: t.(:back), callback_data: "menu:find_coach:page:1" }],
            [{ text: t.(:main_menu_btn), callback_data: "menu:main" }]
          ]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end
      end
    end
  end
end
