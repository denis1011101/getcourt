class ParticipationNotifier
  def self.notify_owner(game, actor, action:)
    owner = game.user
    return unless owner

    game_url = "#{app_host}/games/#{game.id}"
    notification = NotificationDelivery::Notification.new(
      subject: lambda do |locale|
        I18n.t("user_mailer.notification.participation_subject", locale: locale, game_id: game.id)
      end,
      body: ->(locale, channel) { notification_text(game, actor, action, locale, channel, game_url) },
      actions: lambda do |locale|
        [ { label: I18n.t("user_mailer.notification.view_game", locale: locale), url: game_url, telegram: false } ]
      end
    )

    NotificationDelivery.deliver(user: owner, notification: notification)
  end

  def self.notification_text(game, actor, action, locale, channel, game_url)
    name = actor_name(actor, locale, channel)
    date = game.respond_to?(:next_date) ? (game.next_date || game.date) : game.date
    time = game.respond_to?(:next_time) ? (game.next_time || game.time) : game.time
    date_text = date ? I18n.l(date, format: :telegram, locale: locale) : "—"
    time_text = Telegram::Helpers::GameFormatting.format_time_hhmm(time, locale: locale) || "—:--"
    action_text = Telegram::I18n.t("participation_#{action}".to_sym, locale: locale)
    text = Telegram::I18n.t(
      :participation_notification,
      locale: locale,
      name: name,
      action: action_text,
      date: date_text,
      time: time_text
    )
    "#{text}\n\n#{game_url}"
  end
  private_class_method :notification_text

  def self.actor_name(actor, locale, channel)
    if actor.respond_to?(:guest?) && actor.guest?
      "#{actor.guest_name} (#{Telegram::I18n.t(:guest_badge, locale: locale)})"
    elsif actor.is_a?(String)
      actor
    else
      fallback = "#{Telegram::I18n.t(:user_fallback, locale: locale)} ##{actor&.id}"
      Telegram::Helpers::UserLookup.display_name(actor, fallback: fallback, channel: channel)
    end
  end
  private_class_method :actor_name

  def self.app_host
    ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
  end
  private_class_method :app_host
end
