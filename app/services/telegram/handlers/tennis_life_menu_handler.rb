module Telegram
  module Handlers
    class TennisLifeMenuHandler
      RATING_LIMIT = 10

      class << self
        include Telegram::Handlers::ReplyHelpers

        def show(chat_id, message_id: nil)
          locale = Telegram::Helpers::UserLookup.locale_for(chat_id)
          t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }

          posts = fetch_recent_posts(limit: 5)
          rating_rows = fetch_rating_rows(limit: RATING_LIMIT)
          stats = fetch_stats
          scoreboard_text = TennisScoreboard::Fetcher.telegram_text

          lines = [ t.(:tennis_life_title).to_s, "" ]

          lines.concat(stats_lines(stats, locale: locale))
          lines << ""
          lines << refreshed_at_line(locale)
          lines << ""

          if scoreboard_text.present?
            lines << (locale.to_s.start_with?("ru") ? "Теннисные события:" : "Tennis scoreboard:")
            lines << scoreboard_text
            lines << ""
          end

          lines << t.(:rating_title).to_s
          if rating_rows.any?
            rating_rows.each_with_index do |row, idx|
              lines << t.(:rating_row, rank: idx + 1, name: display_name_for(row[:user]), games: row[:games], wins: row[:wins], pct: row[:pct])
            end
          else
            lines << t.(:no_rating_data)
          end

          lines << ""
          lines << t.(:tennis_life_feed_title).to_s
          if posts.any?
            posts.each do |post|
              channel = post.telegram_channel
              channel_name = channel&.username.to_s.delete_prefix("@").presence || "channel"
              date = post.published_at&.strftime("%d.%m.%Y") || "—"
              link = "https://t.me/#{channel_name}/#{post.message_id}"
              preview = post.text.to_s.strip.gsub(/\s+/, " ").truncate(110)

              lines << "#{date} — @#{channel_name}"
              lines << preview if preview.present?
              lines << link
              lines << ""
            end
          else
            random_post = TennisLife::TelegramPostsFetcher.random_post
            if random_post
              lines << "#{random_post["channel_name"]}:"
              lines << random_post["text"].to_s.strip.gsub(/\s+/, " ").truncate(200)
              lines << random_post["url"]
            else
              lines << t.(:tennis_life_no_posts).to_s
            end
          end

          text = lines.join("\n")
          buttons = [
            [ { text: (locale.to_s.start_with?("ru") ? "Обновить" : "Refresh"), callback_data: "menu:tennis_life" } ],
            [ { text: t.(:main_menu_btn), callback_data: "menu:main" } ]
          ]

          if message_id.present?
            Telegram::Api.edit_message_with_buttons(chat_id, message_id, text, buttons, parse_mode: nil)
          else
            Telegram::Api.send_with_buttons(chat_id, text, buttons, parse_mode: nil)
          end
        end

        private

        def fetch_stats
          total_hours = PlayerStatistic.sum(:singles_hours).to_f + PlayerStatistic.sum(:doubles_hours).to_f
          total_hours_value = total_hours.round(1)
          total_hours_value = total_hours_value.to_i if total_hours_value == total_hours_value.to_i

          {
            hours_played: total_hours_value,
            players_in_rating: fetch_rating_rows(limit: nil).size,
            courts: Court.count
          }
        end

        def stats_lines(stats, locale: :ru)
          if locale.to_s.start_with?("ru")
            [
              "Статистика GetCourt:",
              "• Сыграно часов: #{stats[:hours_played]}",
              "• Игроков в рейтинге: #{stats[:players_in_rating]}",
              "• Кортов: #{stats[:courts]}"
            ]
          else
            [
              "GetCourt stats",
              "• Hours played: #{stats[:hours_played]}",
              "• Players in rating: #{stats[:players_in_rating]}",
              "• Courts: #{stats[:courts]}"
            ]
          end
        end

        def refreshed_at_line(locale)
          label = locale.to_s.start_with?("ru") ? "Обновлено" : "Updated"
          "#{label}: #{Time.current.strftime("%H:%M:%S")}"
        end

        def fetch_rating_rows(limit:)
          stats = PlayerStatistic
            .joins(:user)
            .includes(:user)
            .where("COALESCE(player_statistics.singles_games, 0) + COALESCE(player_statistics.doubles_games, 0) > 0")

          rows = stats.map do |ps|
            games = ps.singles_games.to_i + ps.doubles_games.to_i
            wins = ps.singles_wins.to_i + ps.doubles_wins.to_i
            pct = games.positive? ? (wins.to_f / games * 100).round(1) : 0.0

            { user: ps.user, games: games, wins: wins, pct: pct }
          end
          .sort_by { |row| [ -row[:pct], -row[:wins], -row[:games] ] }

          limit ? rows.first(limit) : rows
        end

        def display_name_for(user)
          Telegram::Helpers::UserLookup.display_name(user, fallback: user&.id ? "User ##{user.id}" : "Unknown")
        end

        def fetch_recent_posts(limit: 5)
          if defined?(TelegramPost)
            TelegramPost.includes(:telegram_channel)
                        .joins(:telegram_channel)
                        .where.not(message_id: nil)
                        .where.not(telegram_channels: { username: [ nil, "" ] })
                        .order(published_at: :desc)
                        .limit(limit)
                        .to_a
          else
            []
          end
        rescue => e
          Rails.logger.error "[TennisLifeMenuHandler] #{e.class}: #{e.message}"
          []
        end
      end
    end
  end
end
