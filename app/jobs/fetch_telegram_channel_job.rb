class FetchTelegramChannelJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    channel = TelegramChannel.find(channel_id)
    # TelegramFetcher — ваша обертка над Bot API / TDLib / Telethon
    msgs = TelegramFetcher.fetch_for(channel.username, since_message_id: channel.last_message_id)
    msgs.each do |m|
      post = TelegramPost.create_with(text: m[:text], extra: m[:extra], published_at: m[:date])
                         .find_or_create_by(telegram_channel: channel, message_id: m[:message_id])
      TranslateTelegramPostJob.perform_later(post.id) if post.text_en.blank? && m[:text].present?
      channel.update_column(:last_message_id, m[:message_id]) if m[:message_id] && (channel.last_message_id || 0) < m[:message_id]
    end
  end
end
