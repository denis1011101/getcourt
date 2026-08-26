class NotifyPrebookingOwnerJob < ApplicationJob
  queue_as :default

  def perform(game_id, user_id, batch_ts)
    cache_key = "prebooking_notify:#{game_id}:#{user_id}"
    return unless Rails.cache.read(cache_key).to_s == batch_ts.to_s

    Rails.cache.delete(cache_key)

    game = Game.find_by(id: game_id)
    requester = User.find_by(id: user_id)
    owner = game&.user
    return unless game && requester && owner

    pending = game.prebookings.where(user_id: requester.id, status: "pending")
    return if pending.empty?

    game_url = "#{app_host}/games/#{game.id}"
    notification = NotificationDelivery::Notification.new(
      subject: lambda do |locale|
        I18n.t("user_mailer.notification.prebooking_subject", locale: locale, game_id: game.id)
      end,
      body: ->(locale, channel) { notification_text(game, requester, pending, locale, channel, game_url) },
      actions: ->(locale) { notification_actions(game, requester, locale, game_url) }
    )

    NotificationDelivery.deliver(user: owner, notification: notification)
  end

  private

  def notification_text(game, requester, pending, locale, channel, game_url)
    fallback = Telegram::I18n.t(:user_fallback, locale: locale)
    name = Telegram::Helpers::UserLookup.display_name(requester, fallback: fallback, channel: channel)
    dates = pending.map(&:date).sort.map { |date| I18n.l(date, format: :telegram, locale: locale) }.join(", ")
    request = Telegram::I18n.t(:prebooking_request, locale: locale, game_id: game.id, name: name)
    dates_line = Telegram::I18n.t(:dates_label, locale: locale, dates: dates)
    [ request, dates_line, game_url ].join("\n")
  end

  def notification_actions(game, requester, locale, game_url)
    [
      {
        label: Telegram::I18n.t(:approve_all, locale: locale),
        callback_data: "game:approve_all_prebookings:#{game.id}:#{requester.id}",
        row: 0,
        url: game_url
      },
      {
        label: Telegram::I18n.t(:reject_all, locale: locale),
        callback_data: "game:reject_all_prebookings:#{game.id}:#{requester.id}",
        row: 0
      }
    ]
  end

  def app_host
    ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
  end
end
