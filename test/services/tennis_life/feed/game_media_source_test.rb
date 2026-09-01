require "test_helper"

class TennisLife::Feed::GameMediaSourceTest < ActiveSupport::TestCase
  MAX_AGE = TennisLife::Feed::Sources::Base::MAX_AGE
  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze

  setup do
    @snapshot = 1.minute.from_now.change(usec: 0)
  end

  test "the feed kind survives the inflector" do
    assert_equal "game_media", TennisLife::Feed::Sources::GameMedia.new(snapshot_ts: @snapshot).kind
  end

  test "a fresh attachment shows up and a stale one does not" do
    fresh = create_medium(created_at: @snapshot - 2.days)
    stale = create_medium(created_at: @snapshot - MAX_AGE - 1.day)

    ids = source_ids

    assert_includes ids, fresh.id
    assert_not_includes ids, stale.id
  end

  test "a hidden attachment stays out of the feed" do
    medium = create_medium
    medium.hide!

    assert_not_includes source_ids, medium.id
  end

  test "an attachment without the Tennis Life checkbox stays out of the feed" do
    medium = create_medium(show_in_feed: false)

    assert_not_includes source_ids, medium.id
  end

  test "the loader refuses to serve an attachment unticked after the order was built" do
    medium = create_medium
    medium.update!(show_in_feed: false)

    cards = TennisLife::Feed::Loader.new([ [ "game_media", medium.id ] ], snapshot_ts: @snapshot).load

    assert_empty cards
  end

  test "media from a tournament game stays private" do
    tournament_game = Game.create!(court: courts(:feed_approved), user: users(:one), date: Date.current + 2.days)
    # Через update_column: игру с турниром валидации привязывают к его датам и
    # кортам, а здесь проверяется только фильтр ленты.
    tournament_game.update_column(:tournament_id, tournaments(:one).id)
    medium = create_medium(game: tournament_game)

    assert_not_includes source_ids, medium.id
  end

  test "the loader hands the card back with its game and author" do
    medium = create_medium

    cards = TennisLife::Feed::Loader.new([ [ "game_media", medium.id ] ], snapshot_ts: @snapshot).load

    assert_equal 1, cards.size
    assert_equal medium.id, cards.first.record.id
    assert_equal medium.game_id, cards.first.record.game.id
  end

  test "the loader refuses to serve an attachment hidden after the order was built" do
    medium = create_medium
    medium.hide!

    cards = TennisLife::Feed::Loader.new([ [ "game_media", medium.id ] ], snapshot_ts: @snapshot).load

    assert_empty cards
  end

  private

  def source_ids
    TennisLife::Feed::Sources::GameMedia.new(snapshot_ts: @snapshot).ids
  end

  def create_medium(game: games(:feed_upcoming), created_at: nil, show_in_feed: true)
    medium = GameMedium.new(game: game, user: users(:one), show_in_feed: show_in_feed)
    medium.file.attach(
      io: StringIO.new(Base64.decode64(SAMPLE_PNG)),
      filename: "shot-#{SecureRandom.hex(4)}.png",
      content_type: "image/png"
    )
    medium.save!
    medium.update_column(:created_at, created_at) if created_at
    medium
  end
end
