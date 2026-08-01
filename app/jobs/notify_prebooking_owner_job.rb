class NotifyPrebookingOwnerJob < ApplicationJob
  queue_as :default

  def perform(game_id, user_id, batch_ts)
    cache_key = "prebooking_notify:#{game_id}:#{user_id}"
    cached_ts = Rails.cache.read(cache_key)

    # Only proceed if this is the latest batch (debounce: skip if a newer booking was made)
    return unless cached_ts.to_s == batch_ts.to_s

    Rails.cache.delete(cache_key)

    game = Game.find_by(id: game_id)
    user = User.find_by(id: user_id)
    return unless game && user

    owner = game.user
    return unless owner

    pending_prebookings = game.prebookings.where(user_id: user.id, status: "pending")
    return if pending_prebookings.empty?

    locale = Telegram::I18n.locale_for(owner)
    t = ->(key, **args) { Telegram::I18n.t(key, locale: locale, **args) }
    requester = Telegram::Helpers::UserLookup.display_name(user, fallback: t.(:user_fallback))

    dates_text = pending_prebookings.map(&:date).sort.map { |date| I18n.l(date, format: :telegram, locale: locale) }.join(", ")
    host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
    game_url = "#{host}/games/#{game.id}"
    text = "#{t.(:prebooking_request, game_id: game.id, name: requester)}\n#{t.(:dates_label, dates: dates_text)}\n\n#{game_url}"

    buttons = [
      [
        { text: t.(:approve_all), callback_data: "game:approve_all_prebookings:#{game.id}:#{user.id}" },
        { text: t.(:reject_all), callback_data: "game:reject_all_prebookings:#{game.id}:#{user.id}" }
      ]
    ]

    email_subject, email_body, action_label = I18n.with_locale(NotificationDelivery.email_locale(owner)) do
      [
        I18n.t("user_mailer.notification.prebooking_subject", game_id: game.id),
        I18n.t("user_mailer.notification.prebooking_body", name: requester, dates: dates_text),
        I18n.t("user_mailer.notification.review_game")
      ]
    end

    NotificationDelivery.deliver(
      user: owner,
      telegram_text: text,
      email_subject: email_subject,
      email_body: email_body,
      actions: [ { label: action_label, url: game_url } ],
      telegram_buttons: buttons
    )
  end
end
