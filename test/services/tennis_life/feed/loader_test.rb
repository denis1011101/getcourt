require "test_helper"

class TennisLife::Feed::LoaderTest < ActiveSupport::TestCase
  test "preserves slice order and silently skips deleted records" do
    channel = TelegramChannel.create!(username: "@loader_feed")
    post = TelegramPost.create!(
      telegram_channel: channel,
      message_id: 991_002,
      text: "Loader post",
      published_at: Time.current
    )
    slice = [ [ "fact", "total_hours" ], [ "telegram_post", post.id ], [ "match", -1 ] ]

    cards = TennisLife::Feed::Loader.new(slice, snapshot_ts: Time.current).load

    assert_equal [ "fact", "telegram_post" ], cards.map(&:kind)
    assert_equal [ "total_hours", post.id ], cards.map(&:id)
  end

  test "loads one query group per simple record kind" do
    channel = TelegramChannel.create!(username: "@loader_queries")
    posts = 3.times.map do |index|
      TelegramPost.create!(
        telegram_channel: channel,
        message_id: 992_000 + index,
        text: "Post #{index}",
        published_at: Time.current
      )
    end
    sql = []
    callback = ->(*args) do
      payload = args.last
      sql << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      TennisLife::Feed::Loader.new(
        posts.map { |post| [ "telegram_post", post.id ] },
        snapshot_ts: Time.current
      ).load
    end

    assert_operator sql.size, :<=, 2
  end
end
