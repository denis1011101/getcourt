class GameRequestNotification
  def self.participation(user:, game:, approved:)
    return unless user

    key = approved ? :participation_request_approved_user : :participation_request_rejected_user
    deliver(user, game, key, approved ? "participation_approved" : "participation_rejected")
  end

  def self.prebooking(user:, game:, dates:, approved:)
    return unless user

    key = approved ? :prebooking_request_approved_user : :prebooking_request_rejected_user
    deliver(
      user,
      game,
      key,
      approved ? "prebooking_approved" : "prebooking_rejected",
      dates: Array(dates).compact.sort
    )
  end

  # Организатор записал человека на занятие сам — тот ничего не просил, поэтому
  # и текст не про «одобрено», а про «вас записали». Записать может и админ
  # или тренер, поэтому называем того, кто записал, а не «организатора».
  def self.prebooking_assigned(user:, game:, date:, by: nil)
    return unless user

    deliver(user, game, :prebooking_assigned_user, "prebooking_assigned", dates: [ date ], by: by)
  end

  def self.participation_added(user:, game:, by: nil)
    return unless user

    deliver(user, game, :participation_added_user, "participation_added", by: by)
  end

  def self.deliver(user, game, text_key, subject_key, dates: nil, by: nil)
    game_url = Rails.application.routes.url_helpers.game_url(game, host: app_host)
    # Без e-mail: broadcast_label почту автора не показывает.
    actor = by&.broadcast_label
    notification = NotificationDelivery::Notification.new(
      subject: lambda do |locale|
        args = { game_id: game.id, game: game_reference(game, locale, with_date: dates.nil?) }
        args[:dates] = localized_dates(dates, locale, :long) if dates
        I18n.t("user_mailer.notification.#{subject_key}_subject", locale: locale, **args)
      end,
      body: lambda do |locale|
        args = { game_id: game.id, game: game_reference(game, locale, with_date: dates.nil?) }
        args[:dates] = localized_dates(dates, locale, :telegram) if dates
        text = Telegram::I18n.t(text_key, locale: locale, **args)
        text += " #{Telegram::I18n.t(:"#{text_key}_by", locale: locale, actor: actor)}" if actor
        "#{text}\n\n#{game_url}"
      end,
      actions: lambda do |locale|
        [ { label: I18n.t("user_mailer.notification.view_game", locale: locale), url: game_url, telegram: false } ]
      end
    )

    NotificationDelivery.deliver(user: user, notification: notification)
  end
  private_class_method :deliver

  def self.localized_dates(dates, locale, format)
    dates.map { |date| I18n.l(date, format: format, locale: locale) }.join(", ")
  end
  private_class_method :localized_dates

  # id у повторяющейся игры один на все даты, поэтому рядом город и дата —
  # так же, как игра подписана в чате. Если дата уже в тексте, её не дублируем.
  def self.game_reference(game, locale, with_date:)
    return Telegram::Chat::Message.game_label(game, locale: locale) if with_date

    [ "##{game.id}", game.court&.city_name.presence ].compact.join(" ")
  end
  private_class_method :game_reference

  def self.app_host
    ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
  end
  private_class_method :app_host
end
