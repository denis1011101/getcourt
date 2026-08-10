require "test_helper"

class TennisLifeControllerTest < ActionDispatch::IntegrationTest
  SAMPLE_POST = {
    "channel_name" => "TestChan",
    "channel_url" => "https://t.me/test",
    "text" => "Великий матч!",
    "url" => "https://t.me/test/42",
    "published_at" => "2024-06-01T12:00:00Z"
  }.freeze

  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    # Most of these tests exercise the classic index, so pin the flag off
    # instead of inheriting whatever the developer keeps in .env. The tests
    # that want the feed opt in explicitly.
    @previous_feed_flag = ENV.delete("TENNIS_LIFE_FEED")
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
    ENV["TENNIS_LIFE_FEED"] = @previous_feed_flag
  end

  test "should get index" do
    TelegramPost.delete_all
    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, nil) do
      get tennis_life_index_url

      assert_response :success
      assert_includes response.body, I18n.t("tennis_life.index.no_posts")
    end
  end

  test "featured post remains stable inside the cache window" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    samples = 0
    posts = Object.new
    posts.define_singleton_method(:empty?) { false }
    posts.define_singleton_method(:sample) do
      samples += 1
      SAMPLE_POST.merge("text" => "Post #{samples}")
    end

    stub_singleton(TennisLife::TelegramPostsFetcher, :fetch_posts, posts) do
      first = TennisLife::TelegramPostsFetcher.featured_post
      second = TennisLife::TelegramPostsFetcher.featured_post

      assert_equal first, second
      assert_equal 1, samples
    end
  ensure
    Rails.cache = previous_cache if previous_cache
    TennisLife::TelegramPostsFetcher.singleton_class.send(:private, :fetch_posts)
  end

  test "index shows featured telegram post link when present" do
    TelegramPost.delete_all
    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, SAMPLE_POST) do
      get tennis_life_index_url
      assert_response :success
      assert_select "a[href='#{SAMPLE_POST["url"]}']"
    end
  end

  test "index renders telegram widget for featured post with valid url" do
    TelegramPost.delete_all
    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, SAMPLE_POST) do
      get tennis_life_index_url
      assert_response :success
      assert_select "script[data-telegram-post='test/42']"
    end
  end

  test "index renders a featured translation frame without translating synchronously" do
    TelegramPost.delete_all

    stub_singleton(TranslationCache, :fetch, ->(_) { raise "should not be called by index" }) do
      stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, SAMPLE_POST) do
        get tennis_life_index_url

        assert_response :success
        assert_includes response.body, SAMPLE_POST["text"]
        assert_select "turbo-frame#featured_post_translation[src=?]", tennis_life_featured_translation_path
        assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
      end
    end
  end

  test "featured translation renders translated text in its turbo frame" do
    stub_singleton(TranslationCache, :fetch, "Great match!") do
      stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, SAMPLE_POST) do
        get tennis_life_featured_translation_url

        assert_response :success
        assert_not_includes response.body, "<!DOCTYPE html>"
        assert_select "turbo-frame#featured_post_translation", count: 1 do
          assert_select "p", text: "Great match!"
        end
      end
    end
  end

  test "featured translation falls back to original text" do
    stub_singleton(TranslationCache, :fetch, nil) do
      stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, SAMPLE_POST) do
        get tennis_life_featured_translation_url

        assert_response :success
        assert_select "turbo-frame#featured_post_translation", text: SAMPLE_POST["text"]
      end
    end
  end

  test "featured translation renders an empty frame without a featured post" do
    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, nil) do
      get tennis_life_featured_translation_url

      assert_response :success
      assert_select "turbo-frame#featured_post_translation", count: 1
      assert_select "turbo-frame#featured_post_translation p", count: 0
    end
  end

  test "index renders telegram profile link in player rating" do
    users(:one).update_columns(
      name: "Rating Player",
      telegram_username: "rating_player",
      email: "rating_player@example.com"
    )
    match = Match.create!(
      user: users(:one),
      opponent: users(:two),
      mode: "singles",
      outcome: "win",
      played_at: Time.current
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, nil) do
      get tennis_life_index_url

      assert_response :success
      assert_select "a[href='https://t.me/rating_player']", text: "@rating_player"
    end
  ensure
    match&.destroy
  end

  test "index links to full statistics page" do
    match = Match.create!(
      user: users(:one),
      opponent: users(:two),
      mode: "singles",
      outcome: "win",
      played_at: Time.current
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, nil) do
      get tennis_life_index_url

      assert_response :success
      assert_includes response.body, "Season #{Season.current_label}"
      assert_select "a[href='#{tennis_life_statistics_path}']", text: /View all statistics/
    end
  ensure
    match&.destroy
  end

  # Stored posts belong to the feed, so classic keeps showing the single gist
  # post no matter how many of them are in the database.
  test "classic shows the featured gist post and not the stored ones" do
    channel = TelegramChannel.create!(username: "@classic_check", url: "https://t.me/classic_check")
    TelegramPost.create!(
      telegram_channel: channel,
      message_id: 103,
      text: "Пост из базы",
      published_at: Time.current
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, SAMPLE_POST) do
      get tennis_life_classic_url

      assert_response :success
      assert_includes response.body, SAMPLE_POST["text"]
      assert_not_includes response.body, "Пост из базы"
      assert_not_includes response.body, "classic_check/103"
    end
  end

  test "classic falls back to the empty state when the gist has no post" do
    TelegramPost.create!(
      telegram_channel: TelegramChannel.create!(username: "@classic_empty", url: "https://t.me/classic_empty"),
      message_id: 104,
      text: "Пост из базы",
      published_at: Time.current
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, nil) do
      get tennis_life_classic_url

      assert_response :success
      assert_includes response.body, I18n.t("tennis_life.index.no_posts")
    end
  end

  test "feed enqueues translation jobs for posts without english text" do
    TelegramPost.delete_all
    TelegramChannel.delete_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    channel = TelegramChannel.create!(username: "@feed_test", url: "https://t.me/feed_test")
    post = TelegramPost.create!(
      telegram_channel: channel,
      message_id: 101,
      text: "Новый пост",
      text_en: nil,
      published_at: Time.current,
      created_at: 1.day.ago
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, nil) do
      get tennis_life_feed_url

      assert_response :success
      assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.count
      assert_equal TranslateTelegramPostJob, ActiveJob::Base.queue_adapter.enqueued_jobs.last[:job]
      assert_equal [ post.id ], ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]
    end
  end

  test "feed does not enqueue translation jobs for posts with cached english text" do
    TelegramPost.delete_all
    TelegramChannel.delete_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    TelegramPost.create!(
      telegram_channel: TelegramChannel.create!(username: "@feed_ready", url: "https://t.me/feed_ready"),
      message_id: 102,
      text: "Готовый пост",
      text_en: "Ready post",
      published_at: Time.current,
      created_at: 1.day.ago
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :featured_post, nil) do
      get tennis_life_feed_url

      assert_response :success
      assert_equal 0, ActiveJob::Base.queue_adapter.enqueued_jobs.count
    end
  end

  test "feed rejects malformed and future cursors" do
    get tennis_life_feed_url, params: { cursor: "not-a-cursor" }, as: :turbo_stream
    assert_response :bad_request

    future_cursor = TennisLife::Feed::Cursor.new(seed: 1, snapshot_ts: 1.hour.from_now, offset: 0)
    get tennis_life_feed_url, params: { cursor: future_cursor.to_param }, as: :turbo_stream
    assert_response :bad_request
  end

  test "default feed includes recent content without an explicit seed" do
    travel_to Time.zone.local(2026, 8, 9, 12, 5) do
      channel = TelegramChannel.create!(username: "@recent_feed")
      post = TelegramPost.create!(
        telegram_channel: channel,
        message_id: 992_999,
        text: "Recent feed post",
        text_en: "Recent feed post",
        published_at: 10.minutes.ago,
        created_at: 10.minutes.ago
      )

      get tennis_life_feed_url, as: :turbo_stream

      assert_response :success
      assert_includes response.body, %(data-feed-card-id="telegram_post:#{post.id}")
    ensure
      post&.destroy
      channel&.destroy
    end
  end

  test "cursor remains valid while scrolling across midnight" do
    travel_to Time.zone.local(2026, 8, 9, 23, 50)
    cursor = TennisLife::Feed::Cursor.start(seed: 1, snapshot_ts: Time.current.beginning_of_hour)

    travel 20.minutes
    get tennis_life_feed_url, params: { cursor: cursor.to_param }, as: :turbo_stream

    assert_response :success
  ensure
    travel_back
  end

  test "expired cursor returns a restart card" do
    cursor = TennisLife::Feed::Cursor.start(
      seed: 1,
      snapshot_ts: TennisLife::Feed::Cursor::MAX_AGE.ago - 1.minute
    )

    get tennis_life_feed_url, params: { cursor: cursor.to_param }, as: :turbo_stream

    assert_response :gone
    assert_select "turbo-stream[action='replace'][target='tennis-life-feed-sentinel']", count: 1
    assert_includes response.body, I18n.t("tennis_life.feed.expired_title")
    assert_includes response.body, %(href="#{tennis_life_path}")
  end

  # A crawler following a stale cursor link sends */* — it should land on the live
  # feed, not on a 410 turbo-stream fragment it cannot render.
  test "expired cursor redirects clients that do not ask for a turbo stream" do
    cursor = TennisLife::Feed::Cursor.start(
      seed: 1,
      snapshot_ts: TennisLife::Feed::Cursor::MAX_AGE.ago - 1.minute
    )

    get tennis_life_feed_url, params: { cursor: cursor.to_param }, headers: { "HTTP_ACCEPT" => "*/*" }

    assert_response :see_other
    assert_redirected_to tennis_life_path
  end

  test "feed is finite and does not repeat cards between pages" do
    channel = TelegramChannel.create!(username: "@finite_feed")
    25.times do |index|
      TelegramPost.create!(
        telegram_channel: channel,
        message_id: 993_000 + index,
        text: "Feed post #{index}",
        text_en: "Feed post #{index}",
        published_at: Time.current
      )
    end

    seen = []
    kinds = []
    path = tennis_life_feed_path(seed: 123)

    20.times do
      get path, as: :turbo_stream
      assert_response :success

      ids = response.body.scan(/data-feed-card-id="([^"]+)"/).flatten
      assert_empty seen & ids, "duplicates while loading #{path}"
      seen.concat(ids)
      kinds.concat(ids.map { |id| id.split(":", 2).first })

      link_tag = response.body[/<a\b(?=[^>]*data-infinite-feed-target="link")[^>]*>/]
      encoded_path = link_tag&.[](/href="([^"]+)"/, 1)
      path = encoded_path ? CGI.unescapeHTML(encoded_path) : nil
      break unless path
    end

    assert_nil path, "feed did not finish"
    assert_equal seen.size, seen.uniq.size
    assert_operator seen.size, :>=, 25
    assert_equal %w[court_update fact featured_match match player scoreboard telegram_post tournament upcoming_game urgent_search], kinds.uniq.sort
    assert_not_includes response.body, "telegram-widget.js"
  end

  test "feed HTML is noindex and canonical to tennis life" do
    get tennis_life_feed_url, headers: { "HTTP_ACCEPT" => "*/*" }

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select %q(meta[name="robots"][content="noindex, follow"])
    assert_select %q(link[rel="canonical"][href="https://getcourt.co/tennis_life"])
  end

  test "classic is noindex and canonical to tennis life" do
    get tennis_life_classic_url

    assert_response :success
    assert_select %q(meta[name="robots"][content="noindex, follow"])
    assert_select %q(link[rel="canonical"][href="https://getcourt.co/tennis_life"])
  end

  test "feature flag switches index to the new feed and classic remains available" do
    ENV["TENNIS_LIFE_FEED"] = "1"

    get tennis_life_url
    assert_response :success
    assert_select "[data-controller='infinite-feed']", count: 1

    get tennis_life_classic_url
    assert_response :success
    assert_select "[data-controller='infinite-feed']", count: 0
  end

  test "statistics shows full player rating and recent matches" do
    users(:one).update_columns(
      name: "Stats Player",
      telegram_username: "stats_player",
      email: "stats_player@example.com"
    )
    users(:two).update_columns(
      name: "Stats Opponent",
      telegram_username: "stats_opponent",
      email: "stats_opponent@example.com"
    )
    users(:one).player_statistic&.update!(singles_rating: 1516.0, doubles_rating: 1492.0)

    match = Match.create!(
      user: users(:one),
      opponent: users(:two),
      mode: "singles",
      outcome: "win",
      played_at: Time.current,
      score: "6-4 6-3",
      surface: "hard"
    )

    get tennis_life_statistics_url

    assert_response :success
    assert_select "h1", text: "Tennis Player Rankings & Match Results"
    assert_select "h2", text: /Player Rankings & Win Rates/
    assert_select "h2", text: "Recent Match Results"
    assert_select "a[href='https://t.me/stats_player']", text: "@stats_player"
    assert_includes response.body, "What ELO means"
    assert_includes response.body, "1516.0"
    assert_includes response.body, "1492.0"
    assert_includes response.body, "6-4 6-3"
    assert_includes response.body, "Stats Player vs Stats Opponent"
  ensure
    match&.destroy
  end

  test "statistics ranking drops players without a recent match" do
    Match.delete_all
    active = User.create!(email: "rating_active@example.com", name: "Active Player")
    dormant = User.create!(email: "rating_dormant@example.com", name: "Dormant Player")

    travel_to Time.zone.local(2026, 12, 15) do
      Match.create!(user: active, mode: "singles", outcome: "loss", played_at: 1.week.ago)
      Match.create!(user: dormant, mode: "singles", outcome: "win", played_at: Time.zone.local(2026, 2, 1))

      get tennis_life_statistics_url
    end

    assert_response :success
    assert_select "table td", text: "Active Player", count: 1
    assert_select "table td", text: "Dormant Player", count: 0
  end

  test "statistics shows guest names escaped in recent matches" do
    Match.delete_all
    player = User.create!(email: "guest_recent_player@example.com", name: "Guest Recent Player")
    Match.create!(
      user: player,
      mode: "singles",
      outcome: "win",
      played_at: Time.current,
      score: "6-4",
      stats: {
        "team_a_ids" => [ player.id ],
        "team_b_ids" => [],
        "team_b_guest_names" => [ "<script>alert(1)</script>" ]
      }
    )

    get tennis_life_statistics_url

    assert_response :success
    assert_includes response.body, "Guest Recent Player vs &lt;script&gt;alert(1)&lt;/script&gt; (guest)"
    assert_not_includes response.body, "Guest Recent Player vs <script>alert(1)</script> (guest)"
  ensure
    Match.delete_all
    player&.destroy
  end

  test "statistics rating rows use current season match results" do
    travel_to Time.zone.local(2026, 7, 8, 12, 0, 0) do
      Match.delete_all
      users(:one).update_columns(name: "Season Player", email: "season-player@example.com")
      users(:one).player_statistic.update!(singles_games: 99, singles_wins: 99, singles_rating: 1666.6)

      Match.create!(user: users(:one), opponent: users(:two), mode: "singles", outcome: "win", played_at: 1.month.ago)
      Match.create!(user: users(:one), opponent: users(:two), mode: "singles", outcome: "loss", played_at: 2.months.ago)

      get tennis_life_statistics_url

      row = assigns(:rating_rows).find { |rating_row| rating_row[:user].id == users(:one).id }
      assert_equal 2, row[:games]
      assert_equal 1, row[:wins]
      assert_equal 50.0, row[:pct]
      assert_equal 1666.6, row[:singles_rating]
      assert_includes response.body, "Season 2026"
    end
  ensure
    Match.delete_all
  end

  test "statistics excludes players with only previous season matches" do
    travel_to Time.zone.local(2026, 7, 8, 12, 0, 0) do
      Match.delete_all
      old_player = User.create!(name: "Old Season Player", email: "old-season-player@example.com")
      current_player = User.create!(name: "Current Season Player", email: "current-season-player@example.com")

      Match.create!(user: old_player, mode: "singles", outcome: "win", played_at: Season.current_start - 1.day)
      Match.create!(user: current_player, mode: "singles", outcome: "win", played_at: 1.day.ago)

      get tennis_life_statistics_url

      user_ids = assigns(:rating_rows).map { |rating_row| rating_row[:user].id }
      assert_not_includes user_ids, old_player.id
      assert_includes user_ids, current_player.id
    end
  ensure
    Match.delete_all
  end

  test "statistics uses default elo when player statistic is missing" do
    travel_to Time.zone.local(2026, 7, 8, 12, 0, 0) do
      Match.delete_all
      player = User.create!(name: "No Stat Player", email: "no-stat-player@example.com")
      player.player_statistic.destroy!
      Match.create!(user: player, mode: "singles", outcome: "win", played_at: Time.current)

      get tennis_life_statistics_url

      row = assigns(:rating_rows).find { |rating_row| rating_row[:user].id == player.id }
      assert_equal 1500.0, row[:singles_rating]
      assert_equal 1500.0, row[:doubles_rating]
    end
  ensure
    Match.delete_all
  end

  test "statistics includes reset player with current season match" do
    travel_to Time.zone.local(2026, 7, 8, 12, 0, 0) do
      Match.delete_all
      player = User.create!(name: "Reset Season Player", email: "reset-season-player@example.com")
      player.player_statistic.update!(singles_games: 0, singles_wins: 0, singles_rating: nil, stats_reset_at: Time.current)
      Match.create!(user: player, mode: "singles", outcome: "win", played_at: 1.month.ago)

      get tennis_life_statistics_url

      row = assigns(:rating_rows).find { |rating_row| rating_row[:user].id == player.id }
      assert_equal 1, row[:games]
      assert_equal 1, row[:wins]
      assert_equal 100.0, row[:pct]
      assert_equal 1500.0, row[:singles_rating]
    end
  ensure
    Match.delete_all
  end

  test "statistics shows doubles players from stored stats" do
    player = users(:one)
    player.update_columns(name: "Denis", email: "denis_stats@example.com")

    partner = User.create!(email: "partner_stats@example.com", name: "Irina.Karpova.Vv")
    opponent_one = User.create!(email: "opponent_one_stats@example.com", name: "Keklil")
    opponent_two = User.create!(email: "opponent_two_stats@example.com", name: "Ivan")

    match = Match.create!(
      user: player,
      mode: "doubles",
      outcome: "loss",
      played_at: Time.current,
      score: "1-6 1-6",
      stats: {
        "partner_id" => partner.id,
        "opponent_ids" => [ opponent_one.id, opponent_two.id ]
      }
    )

    get tennis_life_statistics_url

    assert_response :success
    assert_includes response.body, "Denis / Irina.Karpova.Vv vs Keklil / Ivan"
    assert_includes response.body, "2v2"
  end

  test "statistics deduplicates mirrored player-centric singles rows" do
    Match.delete_all
    played_at = Time.current.change(usec: 0)

    Match.create!(
      user: users(:one),
      opponent: users(:two),
      mode: "singles",
      outcome: "win",
      played_at: played_at,
      score: "6-4 6-3",
      stats: { "opponent_ids" => [ users(:two).id ] }
    )

    Match.create!(
      user: users(:two),
      opponent: users(:one),
      mode: "singles",
      outcome: "loss",
      played_at: played_at,
      score: "6-4 6-3",
      stats: { "opponent_ids" => [ users(:one).id ] }
    )

    get tennis_life_statistics_url

    assert_response :success
    assert_equal 1, assigns(:recent_matches).size
    assert_select "article", count: 1
    assert_includes response.body, "6-4 6-3"
  ensure
    Match.delete_all
  end

  test "statistics paginates recent matches from newest to oldest" do
    Match.delete_all

    created_matches = 21.times.map do |i|
      Match.create!(
        user: users(:one),
        opponent: users(:two),
        mode: "singles",
        outcome: "win",
        played_at: Time.current + i.minutes,
        score: "6-#{i} 6-0"
      )
    end

    newest = created_matches.max_by(&:played_at)
    oldest = created_matches.min_by(&:played_at)

    get tennis_life_statistics_url

    assert_response :success
    assert_not_nil assigns(:pagy)
    assert_equal 21, assigns(:pagy).count
    assert_equal 2, assigns(:pagy).pages
    assert_equal 12, assigns(:recent_matches).size
    assert_equal newest.id, assigns(:recent_matches).first.id
    assert_includes response.body, newest.score
    assert_not_includes response.body, oldest.score

    get tennis_life_statistics_url, params: { page: 2 }

    assert_response :success
    assert_equal 9, assigns(:recent_matches).size
    assert_equal oldest.id, assigns(:recent_matches).last.id
    assert_includes response.body, oldest.score
  ensure
    Match.delete_all
  end
end
