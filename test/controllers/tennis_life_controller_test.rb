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
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "should get index" do
    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, nil) do
      get tennis_life_index_url
      assert_response :success
    end
  end

  test "index shows random telegram post link when present" do
    TelegramPost.delete_all
    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, SAMPLE_POST) do
      get tennis_life_index_url
      assert_response :success
      assert_select "a[href='#{SAMPLE_POST["url"]}']"
    end
  end

  test "index renders telegram widget for random post with valid url" do
    TelegramPost.delete_all
    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, SAMPLE_POST) do
      get tennis_life_index_url
      assert_response :success
      assert_select "script[data-telegram-post='test/42']"
    end
  end

  test "index renders original text and enqueues async translation on cache miss" do
    TelegramPost.delete_all

    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { raise "should not be called in controller" }) do
      stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, SAMPLE_POST) do
        get tennis_life_index_url

        assert_response :success
        assert_includes response.body, SAMPLE_POST["text"]
        assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.count
        assert_equal TranslateCachedTextJob, ActiveJob::Base.queue_adapter.enqueued_jobs.last[:job]
        assert_equal [ SAMPLE_POST["text"] ], ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]
      end
    end
  end

  test "index uses cached translation without enqueuing job" do
    TelegramPost.delete_all
    TranslationCache.create!(
      text_hash: Digest::MD5.hexdigest(SAMPLE_POST["text"]),
      text_en: "Great match!"
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, SAMPLE_POST) do
      get tennis_life_index_url

      assert_response :success
      assert_includes response.body, "Great match!"
      assert_equal 0, ActiveJob::Base.queue_adapter.enqueued_jobs.count
    end
  end

  test "index renders telegram profile link in player rating" do
    users(:one).update_columns(
      name: "Rating Player",
      telegram_username: "rating_player",
      email: "rating_player@example.com"
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, nil) do
      get tennis_life_index_url

      assert_response :success
      assert_select "a[href='https://t.me/rating_player']", text: "@rating_player"
    end
  end

  test "index links to full statistics page" do
    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, nil) do
      get tennis_life_index_url

      assert_response :success
      assert_select "a[href='#{tennis_life_statistics_path}']", text: /View all statistics/
    end
  end

  test "index enqueues translation jobs for feed posts without english text" do
    TelegramPost.delete_all
    TelegramChannel.delete_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    channel = TelegramChannel.create!(username: "@feed_test", url: "https://t.me/feed_test")
    post = TelegramPost.create!(
      telegram_channel: channel,
      message_id: 101,
      text: "Новый пост",
      text_en: nil,
      published_at: Time.current
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, nil) do
      get tennis_life_index_url

      assert_response :success
      assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.count
      assert_equal TranslateTelegramPostJob, ActiveJob::Base.queue_adapter.enqueued_jobs.last[:job]
      assert_equal [ post.id ], ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]
    end
  ensure
    post&.destroy
    channel&.destroy
  end

  test "index does not enqueue translation jobs for feed posts with cached english text" do
    TelegramPost.delete_all
    TelegramChannel.delete_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    channel = TelegramChannel.create!(username: "@feed_ready", url: "https://t.me/feed_ready")
    post = TelegramPost.create!(
      telegram_channel: channel,
      message_id: 102,
      text: "Готовый пост",
      text_en: "Ready post",
      published_at: Time.current
    )

    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, nil) do
      get tennis_life_index_url

      assert_response :success
      assert_equal 0, ActiveJob::Base.queue_adapter.enqueued_jobs.count
    end
  ensure
    post&.destroy
    channel&.destroy
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
    assert_select "h2", text: "Player Rankings & Win Rates"
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
