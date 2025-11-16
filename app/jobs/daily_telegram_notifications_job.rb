class DailyTelegramNotificationsJob < ApplicationJob
  queue_as :default

  # day_offset: 0 => today, 1 => tomorrow
  def perform(day_offset = 0)
    target_date = Date.current + day_offset
    games = Game.where("date = ? OR next_date = ?", target_date, target_date)
    games.find_each do |game|
      owner = game.user
      next unless owner&.telegram_chat_id.present?
      time = (game.respond_to?(:next_time) ? (game.next_time || game.time) : game.time)
      time_str = time&.strftime("%H:%M") || "—:--"
      when_text = day_offset == 1 ? "tomorrow" : "today"
      text = "Reminder: you have a game #{when_text} (#{target_date.strftime('%Y-%m-%d')}) at #{time_str} on #{game.court&.name}. Participants: #{game.participations.count}"
      SendTelegramNotificationJob.perform_later(owner.telegram_chat_id, text)
    end
  end
end
