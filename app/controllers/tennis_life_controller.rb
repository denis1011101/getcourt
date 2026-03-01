class TennisLifeController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index ]

  TELEGRAM_CHANNELS = [
    { name: "ТенниСММ", username: "@tennisnewsmm", url: "https://t.me/tennisnewsmm" },
    { name: "Ноги Руне 🎾🎾🎾", username: "@nogirune", url: "https://t.me/nogirune" },
    { name: "Теннисология", username: "@tennisologia", url: "https://t.me/tennisologia" },
    { name: "Теннис+", username: "@tennispls", url: "https://t.me/tennispls" },
    { name: "ТеннисДрот", username: "@tennisdrot", url: "https://t.me/tennisdrot" }
  ].freeze

  FEED_LIMIT = 20
  RATING_LIMIT = 10

  def index
    @tennis_score_raw = TennisScoreboard::Fetcher.raw_text

    allowed_usernames = TELEGRAM_CHANNELS.map { |c| c[:username].to_s.delete_prefix("@").downcase }

    @feed_posts = TelegramPost
      .includes(:telegram_channel)
      .joins(:telegram_channel)
      .where.not(message_id: nil)
      .where.not(telegram_channels: { username: [ nil, "" ] })
      .where("LOWER(telegram_channels.username) IN (?)", allowed_usernames)
      .order(published_at: :desc)
      .limit(FEED_LIMIT)

    rating_rows = build_rating_rows
    @rating_rows = rating_rows.first(RATING_LIMIT)

    @stats_cards = [
      { title: "Сыграно игр", value: Game.count },
      { title: "Игроков в рейтинге", value: rating_rows.size },
      { title: "Кортов", value: Court.count },
      { title: "Участий в играх", value: Participation.count }
    ]
  end

  private

  def build_rating_rows
    stats = PlayerStatistic
      .joins(:user)
      .includes(:user)
      .where("COALESCE(player_statistics.singles_games, 0) + COALESCE(player_statistics.doubles_games, 0) > 0")

    stats.map do |ps|
      games = ps.singles_games.to_i + ps.doubles_games.to_i
      wins = ps.singles_wins.to_i + ps.doubles_wins.to_i
      pct = games.positive? ? (wins.to_f / games * 100).round(1) : 0.0

      {
        user: ps.user,
        games: games,
        wins: wins,
        pct: pct
      }
    end.sort_by { |row| [ -row[:pct], -row[:wins], -row[:games] ] }
  end
end
