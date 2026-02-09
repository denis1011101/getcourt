class DailyTelegramNotificationsJob < ApplicationJob
  queue_as :default

  # day_offset: 0 => today, 1 => tomorrow
  def perform(day_offset = 0)
    target_date = Date.current + day_offset

    # Только реальные колонки
    scope = Game.where("date = ? OR recurring = ?", target_date, true)

    scope.find_each do |game|
      occurrence_date = if game.recurring
                          game.date && game.date >= Date.current ? game.date : game.next_date
                        else
                          game.date
                        end
      next unless occurrence_date == target_date

      # Отправляем всем участникам (Participation)
      recipients = game.participations.includes(:user).map(&:user).compact.uniq
      next if recipients.empty?

      time = game.next_time || game.time
      time_str = time&.strftime("%H:%M") || "—:--"
      when_text = day_offset == 1 ? "tomorrow" : "today"
      court_name = game.court&.name || "unknown court"
      participants = recipients.map do |u|
        u.telegram_username.presence ? "@#{u.telegram_username}" : (u.name.presence || u.email.presence)
      end.compact

      participants_text = participants.join("\n")

      game_url = "https://getcourt.co/games/#{game.id}"
      text = "Reminder: you have a game #{when_text} (#{target_date.strftime('%Y-%m-%d')}) at #{time_str} on #{court_name}.\nParticipants:\n#{participants_text}\n\n#{game_url}"

      recipients.each do |recipient|
        next unless recipient&.telegram_chat_id.present?
        SendTelegramNotificationJob.perform_later(recipient.telegram_chat_id, text)
      end
    end
  end
end
