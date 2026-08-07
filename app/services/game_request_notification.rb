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

  def self.deliver(user, game, text_key, subject_key, dates: nil)
    game_url = Rails.application.routes.url_helpers.game_url(game, host: app_host)
    notification = NotificationDelivery::Notification.new(
      subject: lambda do |locale|
        args = { game_id: game.id }
        args[:dates] = localized_dates(dates, locale, :long) if dates
        I18n.t("user_mailer.notification.#{subject_key}_subject", locale: locale, **args)
      end,
      body: lambda do |locale|
        args = { game_id: game.id }
        args[:dates] = localized_dates(dates, locale, :telegram) if dates
        "#{Telegram::I18n.t(text_key, locale: locale, **args)}\n\n#{game_url}"
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

  def self.app_host
    ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
  end
  private_class_method :app_host
end
