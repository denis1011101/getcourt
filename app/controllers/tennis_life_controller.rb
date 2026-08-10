require "digest"

class TennisLifeController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index classic feed statistics featured_translation]
  before_action :set_secondary_page_meta, only: %i[classic feed]

  FEED_PAGE_SIZE = 20
  PINNED_RATING_LIMIT = 3
  RATING_LIMIT = 10
  MATCHES_PER_PAGE = 20
  ACTIVE_RATING_MONTHS = 6

  def index
    if tennis_life_feed_enabled?
      prepare_feed(initial_feed_cursor)
      render :feed_index
    else
      prepare_classic
    end
  end

  def classic
    prepare_classic
    render :index
  end

  def feed
    cursor = TennisLife::Feed::Cursor.parse(params[:cursor])
    if params[:cursor].present? && cursor.nil?
      return render_expired_feed if TennisLife::Feed::Cursor.expired?(params[:cursor])

      return head :bad_request
    end

    prepare_feed(cursor || initial_feed_cursor)

    respond_to do |format|
      format.html { render :feed_index }
      format.turbo_stream
    end
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

  def set_secondary_page_meta
    @meta_robots = "noindex, follow"
    @canonical_url = "https://#{ApplicationHelper.canonical_host_for(request)}#{tennis_life_path}"
  end

  def prepare_classic
    @season_label = Season.current_label
    @tennis_score_raw = TennisScoreboard::Fetcher.raw_text
    # Classic shows a single featured post. The stored posts belong to the feed,
    # where they are interleaved with the other cards.
    @random_telegram_post = TennisLife::TelegramPostsFetcher.featured_post

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

  # What the feed shows. Each kind is produced by a source in
  # TennisLife::Feed::Sources and rendered by app/views/tennis_life/feed/_<kind>.html.erb;
  # Builder::SOURCE_CLASSES is the registry, and the weight next to each source decides
  # how densely it appears. Keep this list in sync when a source is added or dropped.
  #
  #   telegram_post  — posts from the tracked Telegram channels
  #   match          — a played match with its score (mirror rows are deduped)
  #   player         — a rating player, minus the three pinned at the top
  #   upcoming_game  — a future game that still has free spots
  #   urgent_search  — same, but the organiser flagged an urgent player search
  #   tournament     — a tournament with its participants
  #   featured_match — the active promo match behind the homepage banner
  #   scoreboard     — the live scoreboard fetched from the gist
  #   court_update   — a court correction the community got approved
  #   fact           — a computed community stat (hours played, courts, players)
  #
  # Court cards were dropped deliberately: a bare court with "0 games organized here"
  # carried no news value.
  def prepare_feed(cursor)
    @season_label = Season.current_label
    rating_rows = build_rating_rows(snapshot_ts: cursor.snapshot_ts)
    rating_rows.each_with_index { |row, index| row[:rank] = index + 1 }
    @pinned_rating_rows = rating_rows.first(PINNED_RATING_LIMIT)
    excluded_player_ids = @pinned_rating_rows.map { |row| row[:user].id }

    order = TennisLife::Feed::Builder.new(
      seed: cursor.seed,
      snapshot_ts: cursor.snapshot_ts,
      excluded_player_ids: excluded_player_ids
    ).ordered_ids
    slice = order[cursor.offset, FEED_PAGE_SIZE] || []

    @cards = TennisLife::Feed::Loader.new(
      slice,
      snapshot_ts: cursor.snapshot_ts,
      player_rows: rating_rows
    ).load
    @next_cursor = cursor.advance(slice.size) if cursor.offset + slice.size < order.size
    @feed_seed = cursor.seed
    @feed_snapshot_ts = cursor.snapshot_ts
    enqueue_feed_post_translations(@cards.filter_map { |card| card.record if card.kind == "telegram_post" })
  end

  def initial_feed_cursor
    seed_param = params[:seed].to_s
    explicit_seed = Integer(seed_param, 10) if seed_param.match?(/\A\d{1,10}\z/)
    valid_explicit_seed = explicit_seed&.between?(0, TennisLife::Feed::Cursor::MAX_SEED)

    seed =
      if valid_explicit_seed
        explicit_seed
      else
        Digest::SHA256.hexdigest(Date.current.iso8601).first(8).to_i(16) % (2**31)
      end
    snapshot_ts = valid_explicit_seed ? Time.current : Time.current.beginning_of_hour

    TennisLife::Feed::Cursor.start(seed: seed, snapshot_ts: snapshot_ts)
  rescue ArgumentError, TypeError
    TennisLife::Feed::Cursor.start(
      seed: Digest::SHA256.hexdigest(Date.current.iso8601).first(8).to_i(16) % (2**31),
      snapshot_ts: Time.current.beginning_of_hour
    )
  end

  def render_expired_feed
    @feed_expired = true

    respond_to do |format|
      format.html { redirect_to tennis_life_path, status: :see_other }
      format.turbo_stream { render :feed, status: :gone }
    end
  end

  def tennis_life_feed_enabled?
    ENV["TENNIS_LIFE_FEED"] == "1"
  end

  def enqueue_feed_post_translations(posts)
    posts.each do |post|
      next if post.text_en.present?
      next if post.text.to_s.strip.blank?

      TranslateTelegramPostJob.perform_later(post.id)
    end
  end

  def build_rating_rows(snapshot_ts: Time.current)
    active_user_ids = recently_active_user_ids(snapshot_ts)
    seasonal_rows = Match
      .where(created_at: ..snapshot_ts, played_at: Season.current_start..snapshot_ts)
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
  def recently_active_user_ids(snapshot_ts)
    Match
      .where(created_at: ..snapshot_ts, played_at: (snapshot_ts - ACTIVE_RATING_MONTHS.months)..snapshot_ts)
      .distinct
      .pluck(:user_id)
      .to_set
  end

  def build_recent_match_events
    relation = Match.includes(:user, :opponent, :game).order(played_at: :desc, id: :desc)
    TennisLife::Feed::Sources::Matches.representatives(relation)
  end
end
