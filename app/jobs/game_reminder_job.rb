class GameReminderJob < ApplicationJob
  queue_as :default

  def perform(day_offset = 0)
    target_date = Date.current + day_offset
    scope = Game.where("date = ? OR recurring = ?", target_date, true)

    scope.find_each do |game|
      occurrence_date = game.recurring ? recurring_occurrence_date(game) : game.date
      next unless occurrence_date == target_date

      recipients = game.participations.includes(:user).map(&:user).compact.uniq
      next if recipients.empty?

      recipients.each do |recipient|
        NotificationDelivery.deliver(
          user: recipient,
          notification: notification_for(game, target_date, recipients, day_offset)
        )
      end
    end

    deliver_coach_reminders if day_offset.to_i.zero?
  end

  private

  def deliver_coach_reminders
    today = Time.current.in_time_zone("Asia/Yekaterinburg").to_date
    candidate_dates = [ today, today + 1.day ]

    Game.where(coach_invitation_status: "accepted").where("date IN (?) OR recurring = ?", candidate_dates, true).find_each do |game|
      next unless game.coach

      target_date = game_before_14_yekaterinburg?(game) ? today + 1.day : today
      next unless occurrence_on?(game, target_date)
      next if game.recurring? && !game.coach_prebookings.exists?(coach_id: game.coach_id, date: target_date)

      participants = game.participations.includes(:user).map(&:user).compact.uniq
      NotificationDelivery.deliver(
        user: game.coach,
        notification: notification_for(game, target_date, participants, target_date == today ? 0 : 1)
      )
    end
  end

  def occurrence_on?(game, target_date)
    return game.date == target_date unless game.recurring?
    return false if game.date.blank? || game.date > target_date

    ((target_date - game.date).to_i % 7).zero? && !game.cancelled_on?(target_date)
  end

  def game_before_14_yekaterinburg?(game)
    value = game.next_time || game.time
    hour =
      if value.respond_to?(:hour)
        value.hour
      else
        value.to_s.split(":").first.to_i
      end
    hour < 14
  end

  def recurring_occurrence_date(game)
    game.date && game.date >= Date.current ? game.date : game.next_date
  end

  def notification_for(game, target_date, recipients, day_offset)
    game_url = "https://getcourt.co/games/#{game.id}"

    NotificationDelivery::Notification.new(
      subject: ->(locale) { I18n.t("user_mailer.notification.game_reminder_subject", locale: locale) },
      body: ->(locale) { reminder_text(game, target_date, recipients, day_offset, locale, game_url) },
      actions: lambda do |locale|
        [ { label: I18n.t("user_mailer.notification.view_game", locale: locale), url: game_url, telegram: false } ]
      end
    )
  end

  def reminder_text(game, target_date, recipients, day_offset, locale, game_url)
    t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
    time = game.next_time || game.time
    time_text = Telegram::Helpers::GameFormatting.format_time_hhmm(time, locale: locale) || "—:--"
    when_text = day_offset == 1 ? t.call(:tomorrow) : t.call(:today)
    court_name = game.court&.name || t.call(:unknown_court)
    participant_names = recipients.filter_map do |user|
      Telegram::Helpers::UserLookup.display_name(user, fallback: t.call(:user_fallback))
    end.join("\n")
    head = t.call(
      :reminder_head,
      when: when_text,
      date: I18n.l(target_date, format: :telegram, locale: locale),
      time: time_text,
      court: court_name
    )
    coach = Telegram::Helpers::GameFormatting.coach_mark(game, locale: locale)
    title = coach ? "#{head} — #{coach}" : "#{head}."

    [ title, "#{t.call(:participants_label)}\n#{participant_names}", game_url ].join("\n\n")
  end
end
