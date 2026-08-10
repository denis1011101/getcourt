module TennisLife
  # Copies the Telegram posts published to the shared gist into telegram_posts.
  # The Tennis Life feed reads posts from that table (Feed::Sources::TelegramPosts),
  # so without this import the gist never reaches the feed.
  class GistPostImporter
    POST_URL = %r{\Ahttps://t\.me/(?<username>\w+)/(?<message_id>\d+)\z}

    Result = Struct.new(:created, :updated, :unchanged, :skipped, keyword_init: true) do
      def to_s
        "created=#{created} updated=#{updated} unchanged=#{unchanged} skipped=#{skipped}"
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(posts: nil)
      @posts = posts
    end

    def call
      result = Result.new(created: 0, updated: 0, unchanged: 0, skipped: 0)
      posts.each { |payload| import(payload, result) }
      result
    end

    private

    def posts
      @posts || TelegramPostsFetcher.all_posts(force: true)
    end

    def import(payload, result)
      match = POST_URL.match(payload["url"].to_s)
      text = payload["text"].to_s.strip

      # A post without a parsable t.me URL has no message_id, and the feed skips
      # rows with a blank text anyway.
      if match.nil? || text.blank?
        result.skipped += 1
        return
      end

      post = TelegramPost.find_or_initialize_by(
        telegram_channel: channel_for(match[:username], payload["channel_name"]),
        message_id: match[:message_id].to_i
      )
      created = post.new_record?

      # An edited post has to lose its stale translation.
      post.text_en = nil if !created && post.text != text
      post.text = text
      post.published_at = parse_time(payload["published_at"])
      # The feed only shows records created at or before the hourly snapshot it
      # pins (Feed::Sources::Base#snapshotted). Stamping an imported post with
      # its publication time instead of the import time keeps it from being
      # invisible until the next hour rolls over.
      post.created_at = post.published_at || Time.current if created

      if created
        result.created += 1
      elsif post.changed?
        result.updated += 1
      else
        result.unchanged += 1
        return
      end

      post.save!
      TranslateTelegramPostJob.perform_later(post.id) if post.text_en.blank?
    end

    def channel_for(username, title)
      channel = TelegramChannel.find_or_initialize_by(username: username)
      channel.url = "https://t.me/#{username}"
      channel.title = title.presence || username
      channel.save! if channel.changed?
      channel
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
