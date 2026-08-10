require "test_helper"

class TennisLife::GistPostImporterTest < ActiveSupport::TestCase
  POSTS = [
    { "channel_name" => "ТеннисДрот", "channel_url" => "https://t.me/tennisdrot",
      "text" => "Дрот выиграл", "url" => "https://t.me/tennisdrot/36322",
      "published_at" => "2026-08-10T19:04:53Z" },
    { "channel_name" => "Теннисология", "channel_url" => "https://t.me/tennisologia",
      "text" => "Новости тенниса", "url" => "https://t.me/tennisologia/17623",
      "published_at" => "2026-08-10T18:08:25Z" }
  ].freeze

  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "creates channels and posts from gist payloads" do
    result = TennisLife::GistPostImporter.call(posts: POSTS)

    assert_equal 2, result.created
    assert_equal 0, result.skipped

    post = TelegramPost.find_by(message_id: 36_322)
    assert_equal "Дрот выиграл", post.text
    assert_equal Time.utc(2026, 8, 10, 19, 4, 53), post.published_at
    assert_equal "tennisdrot", post.telegram_channel.username
    assert_equal "ТеннисДрот", post.telegram_channel.title
    assert_equal "https://t.me/tennisdrot", post.telegram_channel.url
  end

  # The whole point of the import: these rows have to clear the filters the feed
  # source applies (message_id, non-blank text, channel username).
  test "imported posts are picked up by the feed source" do
    imported = TennisLife::GistPostImporter.call(posts: POSTS)
    assert_equal 2, imported.created

    ids = TennisLife::Feed::Sources::TelegramPosts.new(snapshot_ts: 1.minute.from_now).ids

    TelegramPost.where(message_id: [ 36_322, 17_623 ]).each do |post|
      assert_includes ids, post.id
    end
  end

  # The feed pins its snapshot to the top of the hour, so a post stamped with the
  # import time stays invisible until the hour rolls over.
  test "a post imported now is visible in the snapshot the feed pins right away" do
    travel_to Time.utc(2026, 8, 10, 20, 11, 9) do
      TennisLife::GistPostImporter.call(posts: POSTS)

      ids = TennisLife::Feed::Sources::TelegramPosts.new(snapshot_ts: Time.current.beginning_of_hour).ids
      post = TelegramPost.find_by(message_id: 36_322)

      assert_equal Time.utc(2026, 8, 10, 19, 4, 53), post.created_at
      assert_includes ids, post.id
    end
  end

  test "falls back to the import time when the gist has no publication date" do
    travel_to Time.utc(2026, 8, 10, 20, 11, 9) do
      TennisLife::GistPostImporter.call(posts: [ POSTS.first.merge("published_at" => nil) ])

      post = TelegramPost.find_by(message_id: 36_322)
      assert_nil post.published_at
      assert_equal Time.current, post.created_at
    end
  end

  test "re-import does not move created_at of an existing post" do
    travel_to Time.utc(2026, 8, 10, 20, 11, 9) do
      TennisLife::GistPostImporter.call(posts: POSTS)
    end
    original = TelegramPost.find_by(message_id: 36_322).created_at

    travel_to Time.utc(2026, 8, 12, 9, 0, 0) do
      TennisLife::GistPostImporter.call(posts: [ POSTS.first.merge("text" => "правка") ])
    end

    assert_equal original, TelegramPost.find_by(message_id: 36_322).created_at
  end

  test "re-importing the same gist creates nothing new" do
    TennisLife::GistPostImporter.call(posts: POSTS)

    assert_no_difference [ "TelegramPost.count", "TelegramChannel.count" ] do
      result = TennisLife::GistPostImporter.call(posts: POSTS)

      assert_equal 0, result.created
      assert_equal 2, result.unchanged
    end
  end

  test "an edited post is updated and loses its stale translation" do
    TennisLife::GistPostImporter.call(posts: POSTS)
    post = TelegramPost.find_by(message_id: 36_322)
    post.update_column(:text_en, "Drot won")

    edited = [ POSTS.first.merge("text" => "Дрот выиграл в трёх сетах") ]
    result = TennisLife::GistPostImporter.call(posts: edited)

    assert_equal 1, result.updated
    post.reload
    assert_equal "Дрот выиграл в трёх сетах", post.text
    assert_nil post.text_en
  end

  test "skips posts without a parsable t.me url or without text" do
    payloads = [
      POSTS.first.merge("url" => "https://example.com/not-telegram"),
      POSTS.first.merge("url" => "https://t.me/tennisdrot"),
      POSTS.second.merge("text" => "   ")
    ]

    assert_no_difference "TelegramPost.count" do
      result = TennisLife::GistPostImporter.call(posts: payloads)

      assert_equal 3, result.skipped
      assert_equal 0, result.created
    end
  end

  test "enqueues a translation only for posts that lack english text" do
    TennisLife::GistPostImporter.call(posts: POSTS)
    assert_equal 2, enqueued_translation_ids.size

    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    TelegramPost.update_all(text_en: "translated")
    TennisLife::GistPostImporter.call(posts: POSTS)

    assert_empty enqueued_translation_ids
  end

  test "falls back to the channel username when the gist has no channel name" do
    TennisLife::GistPostImporter.call(posts: [ POSTS.first.merge("channel_name" => nil) ])

    assert_equal "tennisdrot", TelegramChannel.find_by(username: "tennisdrot").title
  end

  test "reuses an existing channel instead of duplicating it" do
    TelegramChannel.create!(username: "tennisdrot", url: "https://t.me/tennisdrot", title: "old title")

    assert_no_difference "TelegramChannel.count" do
      TennisLife::GistPostImporter.call(posts: [ POSTS.first ])
    end

    assert_equal "ТеннисДрот", TelegramChannel.find_by(username: "tennisdrot").title
  end

  private

  def enqueued_translation_ids
    ActiveJob::Base.queue_adapter.enqueued_jobs
      .select { |job| job["job_class"] == "TranslateTelegramPostJob" || job[:job] == TranslateTelegramPostJob }
      .map { |job| (job["arguments"] || job[:args]).first }
  end
end
