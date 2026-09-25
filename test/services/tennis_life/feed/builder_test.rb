require "test_helper"

class TennisLife::Feed::BuilderTest < ActiveSupport::TestCase
  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze
  SCOREBOARD = <<~TEXT.freeze
    <b>ATP - SINGLES, US Open (USA), hard</b>
    23:00 - <i>Zverev A.</i> - : - <i>Shelton B.</i>

    <b>WTA - SINGLES, Guadalajara (Mexico), hard</b>
    21:00 - <i>Bucsa C.</i> - : - <i>Andreescu B.</i>
  TEXT

  test "rebuild after cache clear produces the same order" do
    snapshot = Time.current.change(usec: 0)
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    builder = TennisLife::Feed::Builder.new(seed: 9123, snapshot_ts: snapshot)

    first = builder.ordered_ids
    Rails.cache.clear
    second = builder.ordered_ids

    assert_equal first, second
    assert_equal first.size, first.uniq.size
  ensure
    Rails.cache = previous_cache
  end

  test "lead scoreboard tournament is pinned near the top, the rest interleave" do
    channel = TelegramChannel.create!(username: "@scoreboard_pin")
    40.times do |index|
      TelegramPost.create!(telegram_channel: channel, message_id: 995_000 + index, text: "Post #{index}", published_at: Time.current)
    end
    order = stub_singleton(TennisScoreboard::Fetcher, :raw_text, SCOREBOARD) do
      TennisLife::Feed::Builder.new(seed: 7, snapshot_ts: Time.current).send(:build_order)
    end

    assert_equal [ "scoreboard", "us-open-usa" ], order[TennisLife::Feed::Builder::PINNED_SCOREBOARD_POSITION]
    assert_includes order, [ "scoreboard", "guadalajara-mexico" ]
    assert_equal 1, order.count { |entry| entry == [ "scoreboard", "us-open-usa" ] }
  end

  test "the two freshest game media take the 4th and 8th cards around the pinned scoreboard" do
    create_posts("@media_pin", 996_000)
    older = create_medium(created_at: 3.days.ago)
    newest = create_medium(created_at: 1.hour.ago)

    order = stub_singleton(TennisScoreboard::Fetcher, :raw_text, SCOREBOARD) do
      TennisLife::Feed::Builder.new(seed: 7, snapshot_ts: Time.current).send(:build_order)
    end

    assert_equal [ "scoreboard", "us-open-usa" ], order[2]
    assert_equal [ "game_media", newest.id ], order[3]
    assert_equal [ "game_media", older.id ], order[7]
    assert_equal order.size, order.uniq.size
  end

  test "game media older than a week is not pinned and stays in the feed" do
    create_posts("@media_stale", 997_000)
    fresh = create_medium(created_at: 1.hour.ago)
    stale = create_medium(created_at: 10.days.ago)

    order = TennisLife::Feed::Builder.new(seed: 7, snapshot_ts: Time.current).send(:build_order)

    assert_equal [ "game_media", fresh.id ], order[3]
    assert_not_equal [ "game_media", stale.id ], order[7]
    assert_includes order, [ "game_media", stale.id ]
  end

  test "snapshot excludes records created later" do
    snapshot = Time.current.change(usec: 0)
    channel = TelegramChannel.create!(username: "@snapshot_feed")
    post = TelegramPost.create!(
      telegram_channel: channel,
      message_id: 991_001,
      text: "Future post",
      published_at: snapshot
    )
    post.update_columns(created_at: snapshot + 1.hour, updated_at: snapshot + 1.hour)

    order = TennisLife::Feed::Builder.new(seed: 42, snapshot_ts: snapshot).ordered_ids

    assert_not_includes order, [ "telegram_post", post.id ]
  end

  test "excluded pinned players do not reappear in the feed" do
    player_id = users(:one).id
    order = TennisLife::Feed::Builder.new(
      seed: 42,
      snapshot_ts: Time.current,
      excluded_player_ids: [ player_id ]
    ).ordered_ids

    assert_not_includes order, [ "player", player_id ]
  end

  private

  def create_posts(username, first_message_id)
    channel = TelegramChannel.create!(username: username)
    40.times do |index|
      TelegramPost.create!(telegram_channel: channel, message_id: first_message_id + index, text: "Post #{index}", published_at: Time.current)
    end
  end

  def create_medium(created_at:)
    medium = GameMedium.new(game: games(:feed_upcoming), user: users(:one), show_in_feed: true)
    medium.file.attach(
      io: StringIO.new(Base64.decode64(SAMPLE_PNG)),
      filename: "shot-#{SecureRandom.hex(4)}.png",
      content_type: "image/png"
    )
    medium.save!
    medium.update_column(:created_at, created_at)
    medium
  end
end
