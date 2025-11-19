class DailyTelegramNotificationsJob < ApplicationJob
  queue_as :default

  # day_offset: 0 => today, 1 => tomorrow
  def perform(day_offset = 0)
    target_date = Date.current + day_offset

    # Берём игры: либо дата = target_date, либо recurring (потом проверим по occurrence_date)
    scope = Game.where("date = ? OR recurring = ?", target_date, true)

    scope.find_each do |game|
      # Для recurring: если game.date >= Date.current, то первое событие ещё не прошло → используем game.date
      # иначе берём game.next_date (следующее повторение)
      occurrence_date = if game.recurring
                          game.date >= Date.current ? game.date : game.next_date
                        else
                          game.date
                        end

      next unless occurrence_date == target_date

      owner = game.user
      next unless owner&.telegram_chat_id.present?

      time = game.next_time || game.time
      time_str = time&.strftime("%H:%M") || "—:--"
      when_text = day_offset == 1 ? "tomorrow" : "today"
      court_name = game.court&.name || "unknown court"
      participants_count = game.participations.count
      game_url = "https://getcourt.co/games/#{game.id}"
      text = "Reminder: you have a game #{when_text} (#{target_date.strftime('%Y-%m-%d')}) at #{time_str} on #{court_name}. Participants: #{participants_count}\n#{game_url}"

      SendTelegramNotificationJob.perform_later(owner.telegram_chat_id, text)
    end
  end
end
