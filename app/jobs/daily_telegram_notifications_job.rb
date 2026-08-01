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
      game_url = "https://getcourt.co/games/#{game.id}"
      recipients.each do |recipient|
        next unless recipient&.telegram_chat_id.present?

        locale = Telegram::Helpers::UserLookup.locale_for(recipient.telegram_chat_id)
        t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
        time_str = Telegram::Helpers::GameFormatting.format_time_hhmm(time, locale: locale) || "—:--"
        when_text = day_offset == 1 ? t.(:tomorrow) : t.(:today)
        court_name = game.court&.name || t.(:unknown_court)
        participants_text = recipients.map do |user|
          Telegram::Helpers::UserLookup.display_name(user, fallback: t.(:user_fallback))
        end.compact.join("\n")
        reminder_head = t.(:reminder_head,
          when: when_text,
          date: I18n.l(target_date, format: :short, locale: locale),
          time: time_str,
          court: court_name)
        coach = Telegram::Helpers::GameFormatting.coach_mark(game, locale: locale)
        title = [ reminder_head, coach ].compact.join(" — ")
        text = [ title, "#{t.(:participants_label)}\n#{participants_text}" ].join("\n") + "\n\n#{game_url}"
        SendTelegramNotificationJob.perform_later(recipient.telegram_chat_id, text)
      end
    end
  end
end
