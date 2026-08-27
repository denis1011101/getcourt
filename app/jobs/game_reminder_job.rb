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

    accepted = Game.where(coach_invitation_status: "accepted")
      .or(Game.where(second_coach_invitation_status: "accepted"))
      .where("date IN (?) OR recurring = ?", candidate_dates, true)

    accepted.find_each do |game|
      target_date = game_before_14_yekaterinburg?(game) ? today + 1.day : today
      next unless occurrence_on?(game, target_date)

      participants = game.participations.includes(:user).map(&:user).compact.uniq

      game.accepted_coaches.each do |coach|
        next if game.recurring? && !game.coach_prebookings.exists?(coach_id: coach.id, date: target_date)

        NotificationDelivery.deliver(
          user: coach,
          notification: notification_for(game, target_date, participants, target_date == today ? 0 : 1)
        )
      end
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
    subject_key = game.training? ? "training_reminder_subject" : "game_reminder_subject"

    NotificationDelivery::Notification.new(
      subject: ->(locale) { I18n.t("user_mailer.notification.#{subject_key}", locale: locale) },
      body: ->(locale, channel) { reminder_text(game, target_date, recipients, day_offset, locale, channel, game_url) },
      parse_mode: "HTML",
      actions: lambda do |locale|
        [ { label: I18n.t("user_mailer.notification.view_game", locale: locale), url: game_url, telegram: false } ]
      end
    )
  end

  def reminder_text(game, target_date, recipients, day_offset, locale, channel, game_url)
    t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
    esc = Telegram::Helpers::Markup.escaper(channel)
    time = game.next_time || game.time
    time_text = Telegram::Helpers::GameFormatting.format_time_hhmm(time, locale: locale) || "—:--"
    when_text = day_offset == 1 ? t.call(:tomorrow) : t.call(:today)
    court_name = Telegram::Helpers::Markup.court_name(game.court, base_url: game_url, channel: channel) ||
      esc.call(t.call(:unknown_court))
    participant_names = recipients.filter_map do |user|
      esc.call(Telegram::Helpers::UserLookup.display_name(user, fallback: t.call(:user_fallback), channel: channel))
    end.join("\n")
    head = t.call(
      game.training? ? :reminder_head_training : :reminder_head,
      when: when_text,
      date: I18n.l(target_date, format: :telegram, locale: locale),
      time: time_text,
      court: court_name
    )
    coach = Telegram::Helpers::GameFormatting.coach_mark(game, locale: locale, with_names: true, channel: channel)
    title = coach ? "#{head} — #{esc.call(coach)}" : "#{head}."
    program = Telegram::Helpers::GameFormatting.training_program(game, locale: locale)
    program_line = t.call(:program_label, items: esc.call(program)) if program.present?

    [ title, program_line, "#{t.call(:participants_label)}\n#{participant_names}", esc.call(game_url) ].compact.join("\n\n")
  end
end
