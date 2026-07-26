class TennisLifeController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index statistics featured_translation]

  FEED_LIMIT = 20
  RATING_LIMIT = 10
  MATCHES_PER_PAGE = 20
  ACTIVE_RATING_MONTHS = 6

  def index
    @season_label = Season.current_label
    @tennis_score_raw = TennisScoreboard::Fetcher.raw_text
    @random_telegram_post = TennisLife::TelegramPostsFetcher.featured_post

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
    @season_label = Season.current_label
    @rating_rows = build_rating_rows
    @pagy, @recent_matches = pagy_array(build_recent_match_events)
  end

  def featured_translation
    post = TennisLife::TelegramPostsFetcher.featured_post
    text = post && post["text"].to_s.strip.presence
    @text_en = text && (TranslationCache.fetch(text).presence || text)
    render layout: false
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
    active_user_ids = recently_active_user_ids
    seasonal_rows = Match
      .where(played_at: Season.current_start..)
      .group(:user_id)
      .pluck(
        :user_id,
        Arel.sql("COUNT(*)"),
        Arel.sql("SUM(CASE WHEN outcome = 'win' THEN 1 ELSE 0 END)")
      )

    user_ids = seasonal_rows.map(&:first)
    users_by_id = User.where(id: user_ids).index_by(&:id)
    stats_by_user_id = PlayerStatistic.where(user_id: user_ids).index_by(&:user_id)

    seasonal_rows.filter_map do |user_id, games_count, wins_count|
      user = users_by_id[user_id]
      next unless user && active_user_ids.include?(user_id)

      games = games_count.to_i
      wins = wins_count.to_i
      pct = games.positive? ? (wins.to_f / games * 100).round(1) : 0.0
      ps = stats_by_user_id[user_id]

      {
        user: user,
        games: games,
        wins: wins,
        pct: pct,
        singles_rating: (ps&.singles_rating || 1500.0),
        doubles_rating: (ps&.doubles_rating || 1500.0)
      }
    end.sort_by { |row| [ -row[:pct], -row[:wins], -row[:games] ] }
  end

  # A single win back in January shouldn't hold the top spot for the rest of the season.
  def recently_active_user_ids
    Match.where(played_at: ACTIVE_RATING_MONTHS.months.ago..).distinct.pluck(:user_id).to_set
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
