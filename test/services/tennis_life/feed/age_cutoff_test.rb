require "test_helper"

class TennisLife::Feed::AgeCutoffTest < ActiveSupport::TestCase
  MAX_AGE = TennisLife::Feed::Sources::Base::MAX_AGE

  # A minute ahead: `snapshotted` drops anything created after the snapshot, and the
  # records under test are created inside the test itself.
  setup do
    @snapshot = 1.minute.from_now.change(usec: 0)
  end

  test "a telegram post from last season is not news" do
    channel = TelegramChannel.create!(username: "@stale_feed")
    stale = TelegramPost.create!(
      telegram_channel: channel,
      message_id: 771_001,
      text: "Прошлый сезон",
      published_at: @snapshot - MAX_AGE - 1.day
    )
    fresh = TelegramPost.create!(
      telegram_channel: channel,
      message_id: 771_002,
      text: "На этой неделе",
      published_at: @snapshot - 2.days
    )

    ids = TennisLife::Feed::Sources::TelegramPosts.new(snapshot_ts: @snapshot).ids

    assert_includes ids, fresh.id
    assert_not_includes ids, stale.id
  end

  test "matches are cut by when they were played, not when they were entered" do
    stale = Match.create!(
      user: users(:one),
      opponent: users(:two),
      mode: "singles",
      outcome: "win",
      score: "6-0 6-0",
      played_at: @snapshot - MAX_AGE - 1.day
    )

    ids = TennisLife::Feed::Sources::Matches.new(snapshot_ts: @snapshot).ids

    assert_not_includes ids, stale.id
  end

  test "a tournament that finished months ago drops out" do
    stale = Tournament.create!(
      name: "Old Cup",
      user: users(:one),
      start_date: (@snapshot - MAX_AGE - 1.week).to_date,
      end_date: (@snapshot - MAX_AGE - 6.days).to_date
    )

    ids = TennisLife::Feed::Sources::Tournaments.new(snapshot_ts: @snapshot).ids

    assert_not_includes ids, stale.id
  end
end
