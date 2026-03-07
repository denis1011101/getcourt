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
            lines << t.(:tennis_life_no_posts).to_s
          end

          lines << ""
          lines << (locale.to_s.start_with?("ru") ? "Каналы:" : "Channels:")
          TennisLifeController::TELEGRAM_CHANNELS.each do |c|
            lines << "• #{c[:name]} — #{c[:username]}"
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
          {
            games: Game.count,
            courts: Court.count,
            participations: Participation.count
          }
        end

        def stats_lines(stats, locale: :ru)
          if locale.to_s.start_with?("ru")
            [
              "Статистика GetCourt:",
              "• Игр: #{stats[:games]}",
              "• Кортов: #{stats[:courts]}",
              "• Участий: #{stats[:participations]}"
            ]
          else
            [
              "GetCourt stats",
              "• Games: #{stats[:games]}",
              "• Courts: #{stats[:courts]}",
              "• Participations: #{stats[:participations]}"
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

          stats.map do |ps|
            games = ps.singles_games.to_i + ps.doubles_games.to_i
            wins = ps.singles_wins.to_i + ps.doubles_wins.to_i
            pct = games.positive? ? (wins.to_f / games * 100).round(1) : 0.0

            { user: ps.user, games: games, wins: wins, pct: pct }
          end
          .sort_by { |row| [ -row[:pct], -row[:wins], -row[:games] ] }
          .first(limit)
        end

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
