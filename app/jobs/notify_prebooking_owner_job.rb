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
    return unless owner&.telegram_chat_id.present?

    pending_prebookings = game.prebookings.where(user_id: user.id, status: "pending")
    return if pending_prebookings.empty?

    requester = if user.respond_to?(:telegram_username) && user.telegram_username.present?
                  "@#{user.telegram_username}"
                elsif user.respond_to?(:username) && user.username.present?
                  "@#{user.username}"
                else
                  user.name.presence || user.email.presence || "User"
                end

    dates_text = pending_prebookings.map { |pb| pb.date.strftime("%Y-%m-%d") }.sort.join(", ")
    host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
    game_url = "#{host}/games/#{game.id}"
    locale = Telegram::I18n.locale_for(owner)
    text = Telegram::I18n.t(
      :prebooking_request_message,
      locale: locale,
      game_id: game.id,
      requester: requester,
      dates: dates_text,
      url: game_url
    )

    buttons = [
      [
        { text: Telegram::I18n.t(:approve_all_btn, locale: locale), callback_data: "game:approve_all_prebookings:#{game.id}:#{user.id}" },
        { text: Telegram::I18n.t(:reject_all_btn, locale: locale),  callback_data: "game:reject_all_prebookings:#{game.id}:#{user.id}" }
      ]
    ]

    poller = Telegram::Poller.new
    poller.send_api("sendMessage", {
      chat_id: owner.telegram_chat_id,
      text: text,
      reply_markup: { inline_keyboard: buttons }
    }) rescue nil
  end
end
