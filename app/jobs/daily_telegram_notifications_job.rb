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
        locale = Telegram::I18n.locale_for(recipient)
        t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
        time_str = Telegram::Helpers::GameFormatting.format_time_hhmm(time, locale: locale) || "—:--"
        when_text = day_offset == 1 ? t.(:tomorrow) : t.(:today)
        court_name = game.court&.name || t.(:unknown_court)
        participants_text = recipients.map do |user|
          Telegram::Helpers::UserLookup.display_name(user, fallback: t.(:user_fallback))
        end.compact.join("\n")
        reminder_head = t.(:reminder_head,
          when: when_text,
          date: I18n.l(target_date, format: :telegram, locale: locale),
          time: time_str,
          court: court_name)
        coach = Telegram::Helpers::GameFormatting.coach_mark(game, locale: locale)
        title = coach ? "#{reminder_head} — #{coach}" : "#{reminder_head}."
        telegram_text = [ title, "#{t.(:participants_label)}\n#{participants_text}" ].join("\n") + "\n\n#{game_url}"

        email_subject, email_body, action_label = email_reminder(game, recipient, target_date, time, recipients, day_offset)
        NotificationDelivery.deliver(
          user: recipient,
          telegram_text: telegram_text,
          email_subject: email_subject,
          email_body: email_body,
          actions: [ { label: action_label, url: game_url } ]
        )
      end
    end
  end

  private

  def email_reminder(game, recipient, target_date, time, recipients, day_offset)
    I18n.with_locale(NotificationDelivery.email_locale(recipient)) do
      when_text = I18n.t(day_offset == 1 ? "user_mailer.notification.tomorrow" : "user_mailer.notification.today")
      time_text = time&.strftime("%H:%M") || "—:--"
      court_name = game.court&.name || I18n.t("user_mailer.notification.unknown_court")
      coach = game.with_coach? ? " — #{I18n.t('user_mailer.notification.with_coach')}" : "."
      title = I18n.t("user_mailer.notification.game_reminder_body",
        when: when_text,
        date: I18n.l(target_date, format: :long),
        time: time_text,
        court: court_name) + coach
      names = recipients.map { |user| user.name.presence || user.email }.join("\n")
      body = "#{title}\n\n#{I18n.t('user_mailer.notification.participants')}:\n#{names}"

      [ I18n.t("user_mailer.notification.game_reminder_subject"), body, I18n.t("user_mailer.notification.view_game") ]
    end
  end
end
