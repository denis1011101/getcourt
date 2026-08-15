module TennisLife
  module Feed
    module Sources
      class TelegramPosts < Base
        def ids
          recent(snapshotted(TelegramPost), column: :published_at)
            .joins(:telegram_channel)
            .where.not(message_id: nil)
            .where.not(text: [ nil, "" ])
            .where.not(telegram_channels: { username: [ nil, "" ] })
            .distinct
            .pluck(:id)
        end
      end
    end
  end
end
