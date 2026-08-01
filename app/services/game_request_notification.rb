class GameRequestNotification
  def self.participation(user:, game:, approved:)
    return unless user

    locale = Telegram::I18n.locale_for(user)
    telegram_key = approved ? :participation_request_approved_user : :participation_request_rejected_user
    telegram_text = Telegram::I18n.t(telegram_key, locale: locale, game_id: game.id)
    deliver(user, game, telegram_text, approved ? "participation_approved" : "participation_rejected")
  end

  def self.prebooking(user:, game:, dates:, approved:)
    return unless user

    dates = Array(dates).compact.sort
    locale = Telegram::I18n.locale_for(user)
    telegram_dates = dates.map { |date| I18n.l(date, format: :telegram, locale: locale) }.join(", ")
    telegram_key = approved ? :prebooking_request_approved_user : :prebooking_request_rejected_user
    telegram_text = Telegram::I18n.t(telegram_key, locale: locale, game_id: game.id, dates: telegram_dates)
    deliver(user, game, telegram_text, approved ? "prebooking_approved" : "prebooking_rejected", dates: dates)
  end

  def self.deliver(user, game, telegram_text, key, dates: nil)
    game_url = Rails.application.routes.url_helpers.game_url(game, host: app_host)
    subject, body, action_label = I18n.with_locale(NotificationDelivery.email_locale(user)) do
      args = { game_id: game.id }
      args[:dates] = dates.map { |date| I18n.l(date, format: :long) }.join(", ") if dates
      [
        I18n.t("user_mailer.notification.#{key}_subject", **args),
        I18n.t("user_mailer.notification.#{key}_body", **args),
        I18n.t("user_mailer.notification.view_game")
      ]
    end

    NotificationDelivery.deliver(
      user: user,
      telegram_text: "#{telegram_text}\n\n#{game_url}",
      email_subject: subject,
      email_body: body,
      actions: [ { label: action_label, url: game_url } ]
    )
  end
  private_class_method :deliver

  def self.app_host
    ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
  end
  private_class_method :app_host
end
