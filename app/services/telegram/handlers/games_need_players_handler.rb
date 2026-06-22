module Telegram
  module Handlers
    class GamesNeedPlayersHandler
      PER_PAGE = 5

      class << self
        include Telegram::Handlers::ReplyHelpers

        def list_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          page = page.to_i < 1 ? 1 : page.to_i
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          favorite_ids = user&.favorite_court_ids || []

          # Future games where players search is enabled
          open_games = Game.includes(:user, :participations, :court)
                           .where(urgent_player_search: true)
                           .where("recurring = ? OR date >= ?", true, Date.current)
                           .to_a

          # Sort by favorite courts first, then by date (nearest first)
          open_games.sort_by! do |g|
            d = g.respond_to?(:display_date_for_show) ? g.display_date_for_show : g.date
            [ favorite_ids.include?(g.court_id) ? 0 : 1, d || Date.new(9999, 12, 31) ]
          end

          total = open_games.size
          pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
          offset = (page - 1) * PER_PAGE
          games = open_games.slice(offset, PER_PAGE) || []

          header = t.(:games_need_players_title)

          if games.empty?
            text = "#{header}\n\n#{t.(:no_games_need_players)}"
            buttons = [ [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ] ]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
            return
          end

          buttons = games.map do |g|
            label = Telegram::Handlers::GamesHandler.game_label(g, locale: locale)
            [ { text: label, callback_data: "game:show:#{g.id}:1" } ]
          end

          nav = []
          nav << [ { text: t.(:prev_page), callback_data: "menu:games_need_players:page:#{page - 1}" } ] if page > 1
          nav << [ { text: t.(:next_page), callback_data: "menu:games_need_players:page:#{page + 1}" } ] if page < pages
          buttons.concat(nav) unless nav.empty?
          buttons << [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]

          send_or_edit_with_buttons(chat_id, header, buttons, message_id: message_id)
        end
      end
    end
  end
end
