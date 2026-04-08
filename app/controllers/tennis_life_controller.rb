class TennisLifeController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index statistics]

  FEED_LIMIT = 20
  RATING_LIMIT = 10
  MATCHES_PER_PAGE = 20

  def index
    @tennis_score_raw = TennisScoreboard::Fetcher.raw_text
    @random_telegram_post = TennisLife::TelegramPostsFetcher.random_post
    if @random_telegram_post && (text = @random_telegram_post["text"].to_s.strip).present?
      @random_post_text_en = TranslationCache.read(text)
      TranslationCache.enqueue(text) if @random_post_text_en.blank?
    end

    @feed_posts = TelegramPost
      .includes(:telegram_channel)
      .joins(:telegram_channel)
      .where.not(message_id: nil)
      .where.not(telegram_channels: { username: [ nil, "" ] })
      .order(published_at: :desc)
      .limit(FEED_LIMIT)
    enqueue_feed_post_translations(@feed_posts)

    rating_rows = build_rating_rows
    @rating_rows = rating_rows.first(RATING_LIMIT)
    total_hours = PlayerStatistic.sum(:singles_hours).to_f + PlayerStatistic.sum(:doubles_hours).to_f
    total_hours_value = total_hours.round(1)
    total_hours_value = total_hours_value.to_i if total_hours_value == total_hours_value.to_i

    @stats_cards = [
      # { title: "Games played", value: Game.count }, # TODO: придумать как считать, наверное надо в статистику класть просто
      { title: "Hours played", value: total_hours_value },
      { title: "Players in rating", value: rating_rows.size },
      { title: "Courts", value: Court.count }
      # { title: "Tournaments played", value: Tournament.count },
      # { title: "Game participations", value: Participation.count }
    ]
  end

  def statistics
    @rating_rows = build_rating_rows
    @pagy, @recent_matches = pagy_array(build_recent_match_events)
  end

  private

  def enqueue_feed_post_translations(posts)
    posts.each do |post|
      next if post.text_en.present?
      next if post.text.to_s.strip.blank?

      TranslateTelegramPostJob.perform_later(post.id)
    end
  end

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
        pct: pct,
        singles_rating: (ps.singles_rating || 1500.0),
        doubles_rating: (ps.doubles_rating || 1500.0)
      }
    end.sort_by { |row| [ -row[:pct], -row[:wins], -row[:games] ] }
  end

  def build_recent_match_events
    Match.includes(:user, :opponent, :game)
      .order(played_at: :desc, id: :desc)
      .to_a
      .group_by { |match| recent_match_event_key(match) }
      .values
      .map { |group| select_recent_match_representative(group) }
  end

  def recent_match_event_key(match)
    stats = match.stats.to_h

    participants =
      if match.mode == "doubles"
        team_a_ids = normalize_match_ids(stats["team_a_ids"])
        team_b_ids = normalize_match_ids(stats["team_b_ids"])

        if team_a_ids.any? && team_b_ids.any?
          [ team_a_ids, team_b_ids ].sort
        else
          [ normalize_match_ids([ match.user_id, stats["partner_id"] ]), normalize_match_ids(stats["opponent_ids"]) ].sort
        end
      else
        normalize_match_ids([ match.user_id, match.opponent_id, *Array(stats["opponent_ids"]) ])
      end

    [ match.game_id, match.mode, match.played_at&.to_i, match.score.to_s, participants ]
  end

  def select_recent_match_representative(group)
    group.min_by do |match|
      stats = match.stats.to_h
      participants =
        if match.mode == "doubles"
          normalize_match_ids([ *Array(stats["team_a_ids"]), *Array(stats["team_b_ids"]), match.user_id ])
        else
          normalize_match_ids([ match.user_id, match.opponent_id, *Array(stats["opponent_ids"]) ])
        end

      [ participants.index(match.user_id) || participants.length, match.id ]
    end
  end

  def normalize_match_ids(values)
    Array(values).map(&:to_i).reject(&:zero?).uniq.sort
  end
end
