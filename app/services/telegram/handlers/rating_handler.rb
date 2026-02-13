module Telegram
  module Handlers
    class RatingHandler
      PER_PAGE = 10

      class << self
        include Telegram::Handlers::ReplyHelpers

        def list_page(chat_id, page = 1, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          page = [page.to_i, 1].max

          # Build rating from player_statistics + participations
          stats = PlayerStatistic
            .joins(:user)
            .includes(:user)
            .where("COALESCE(player_statistics.singles_games, 0) + COALESCE(player_statistics.doubles_games, 0) > 0")
            .to_a

          # Sort by win percentage desc, then total wins desc, then total games desc
          ranked = stats.map do |ps|
            total_games = ps.singles_games.to_i + ps.doubles_games.to_i
            total_wins  = ps.singles_wins.to_i + ps.doubles_wins.to_i
            pct = total_games > 0 ? (total_wins.to_f / total_games * 100).round(1) : 0.0
            { user: ps.user, games: total_games, wins: total_wins, pct: pct }
          end

          ranked.sort_by! { |r| [-r[:pct], -r[:wins], -r[:games]] }

          total = ranked.size
          pages = [(total.to_f / PER_PAGE).ceil, 1].max
          page = [page, pages].min
          offset = (page - 1) * PER_PAGE
          slice = ranked.slice(offset, PER_PAGE) || []

          if slice.empty?
            text = "#{t.(:rating_title)}\n\n#{t.(:no_rating_data)}"
            buttons = [[{ text: t.(:main_menu_btn), callback_data: "menu:main" }]]
            send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
            return
          end

          lines = slice.each_with_index.map do |r, i|
            rank = offset + i + 1
            name = display_name_for(r[:user])
            t.(:rating_row, rank: rank, name: name, games: r[:games], wins: r[:wins], pct: r[:pct])
          end

          header = pages > 1 ? t.(:rating_page, page: page, pages: pages) : t.(:rating_title)
          text = "#{header}\n\n#{lines.join("\n")}"

          buttons = []
          nav = []
          nav << { text: t.(:prev_page), callback_data: "menu:rating:page:#{page - 1}" } if page > 1
          nav << { text: t.(:next_page), callback_data: "menu:rating:page:#{page + 1}" } if page < pages
          buttons << nav unless nav.empty?
          buttons << [{ text: t.(:main_menu_btn), callback_data: "menu:main" }]

          send_or_edit_with_buttons(chat_id, text, buttons, message_id: message_id)
        end

        private

        def display_name_for(user)
          return "Unknown" unless user
          if user.telegram_username.present?
            "@#{user.telegram_username.delete_prefix('@')}"
          elsif user.name.present?
            user.name
          elsif user.email.present?
            user.email
          else
            "User ##{user.id}"
          end
        end
      end
    end
  end
end
