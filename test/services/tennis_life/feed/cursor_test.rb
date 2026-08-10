require "test_helper"

class TennisLife::Feed::CursorTest < ActiveSupport::TestCase
  test "round trips seed snapshot and offset" do
    snapshot = Time.zone.local(2026, 8, 9, 12, 30, 0)
    cursor = TennisLife::Feed::Cursor.new(seed: 123, snapshot_ts: snapshot, offset: 40)

    parsed = TennisLife::Feed::Cursor.parse(cursor.to_param, now: snapshot)

    assert_equal 123, parsed.seed
    assert_equal snapshot, parsed.snapshot_ts
    assert_equal 40, parsed.offset
  end

  test "rejects malformed future and stale cursors" do
    now = Time.current.change(usec: 0)

    assert_nil TennisLife::Feed::Cursor.parse("not-a-cursor", now: now)
    assert_nil TennisLife::Feed::Cursor.parse("a" * 129, now: now)
    assert_nil TennisLife::Feed::Cursor.parse(
      TennisLife::Feed::Cursor.new(seed: 1, snapshot_ts: now + 1.hour, offset: 0).to_param,
      now: now
    )
    assert_nil TennisLife::Feed::Cursor.parse(
      TennisLife::Feed::Cursor.new(seed: 1, snapshot_ts: now - 2.days, offset: 0).to_param,
      now: now
    )
  end

  test "advance preserves feed identity" do
    cursor = TennisLife::Feed::Cursor.start(seed: 77, snapshot_ts: Time.current)
    advanced = cursor.advance(20)

    assert_equal cursor.seed, advanced.seed
    assert_equal cursor.snapshot_ts, advanced.snapshot_ts
    assert_equal 20, advanced.offset
  end
end
