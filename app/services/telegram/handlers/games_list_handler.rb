module Telegram
  module Handlers
    class GamesListHandler
      PER_PAGE = 5

      class << self
        include Telegram::Handlers::ReplyHelpers

        def list_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          page = page.to_i < 1 ? 1 : page.to_i

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          user_city = user&.city_name.to_s.strip.downcase.presence

          all_games = Game.includes(:user, :participations, :prebooking_cancellations)
                          .where("recurring = ? OR date >= ?", true, Date.current)
                          .to_a

          today = Date.current
          now = Time.zone.now
          now_hhmm = now.hour * 100 + now.min

          mapped_games = all_games.map do |g|
            d = g.display_date_for_show
            sort_date = d || Date.new(9999, 12, 31)

            t_obj = Telegram::Helpers::GameFormatting.resolve_time(g)
            hhmm = 0
            if t_obj.respond_to?(:strftime)
              hhmm = t_obj.strftime("%H%M").to_i
            elsif t_obj.to_s.include?(":")
              parts = t_obj.to_s.split(":")
              hhmm = parts[0].to_i * 100 + parts[1].to_i
            end

            is_future = if sort_date > today
                          true
            elsif sort_date < today
                          false
            else
                          hhmm >= now_hhmm
            end

            same_city = if user_city && g.court&.city_name.to_s.strip.downcase == user_city
                          0
            else
                          1
            end

            { game: g, date: sort_date, time: hhmm, is_future: is_future, city_rank: same_city }
          end

          future_items, past_items = mapped_games.partition { |item| item[:is_future] }
          sorter = ->(item) { [ item[:city_rank], item[:date], item[:time] ] }

          sorted_future = future_items.sort_by(&sorter)
          sorted_past = past_items.sort_by(&sorter)
          sorted_games = (sorted_future + sorted_past).map { |item| item[:game] }

          total = sorted_games.size
          pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
          offset = (page - 1) * PER_PAGE
          games = sorted_games.slice(offset, PER_PAGE) || []

          header = t.(:games_page, page: page, pages: pages)

          if games.empty?
            send_or_edit_text(chat_id, "#{header}\n\n#{t.(:no_games_on_page)}", message_id: message_id)
            return
          end

          buttons = games.map do |g|
            [ { text: Telegram::Handlers::GamesHandler.game_label(g, locale: locale), callback_data: "game:show:#{g.id}:#{page}" } ]
          end

          nav = []
          nav << [ { text: t.(:prev_page), callback_data: "menu:games:page:#{page - 1}" } ] if page > 1
          nav << [ { text: t.(:next_page), callback_data: "menu:games:page:#{page + 1}" } ] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end

        def my_games_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user
            Telegram::Handlers::ReplyHelpers.instance_method(:send_or_edit_text).bind_call(self, chat_id, t.(:no_linked_account), message_id: message_id) rescue nil
            Telegram::Api.send_simple(chat_id, t.(:no_linked_account))
            return
          end

          page = [ page.to_i, 1 ].max

          all_games = Game.includes(:user, :participations, :prebooking_cancellations)
                          .where("games.user_id = :uid OR games.id IN (SELECT game_id FROM participations WHERE user_id = :uid)", uid: user.id)
                          .order(:date, :time).to_a

          total = all_games.size
          pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
          offset = (page - 1) * PER_PAGE
          games = all_games.slice(offset, PER_PAGE) || []

          header = t.(:my_games_page, page: page, pages: pages)

          if games.empty?
            buttons = [ [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ] ]
            send_or_edit_with_buttons(chat_id, "#{header}\n\n#{t.(:no_my_games)}", buttons, message_id: message_id)
            return
          end

          buttons = games.map do |g|
            [ { text: Telegram::Handlers::GamesHandler.game_label(g, locale: locale), callback_data: "game:show:#{g.id}:#{page}" } ]
          end

          nav = []
          nav << [ { text: t.(:prev_page), callback_data: "menu:my_games:page:#{page - 1}" } ] if page > 1
          nav << [ { text: t.(:next_page), callback_data: "menu:my_games:page:#{page + 1}" } ] if page < pages
          buttons.concat(nav) unless nav.empty?

          buttons << [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end
      end
    end
  end
end
