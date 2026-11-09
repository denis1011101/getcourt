class NotifyUrgentPlayerSearchJob < ApplicationJob
  queue_as :default

  def perform(game_id)
    game = Game.includes(:court, :user).find_by(id: game_id)
    return unless game&.urgent_player_search?

    court_city_id = game.court&.city_id
    game_city = City.normalize_name(game.court&.city_name)
    return if court_city_id.blank? && game_city.blank?

    User.where(notify_nearby: true).where.not(id: game.user_id).find_each do |user|
      next unless city_matches?(user: user, court_city_id: court_city_id, game_city: game_city)

      deliver(user, game)
    end
  rescue => e
    Rails.logger.error "[NotifyUrgentPlayerSearchJob] #{e.class}: #{e.message}"
  end

  private

  def city_matches?(user:, court_city_id:, game_city:)
    if court_city_id.present? && user.city_id.present?
      court_city_id == user.city_id
    else
      return false if game_city.blank?

      user_city = City.normalize_name(user.city_name)
      user_city.present? && user_city == game_city
    end
  end

  def deliver(user, game)
    channel = user.notification_channel.presence || (user.telegram_chat_id.present? ? "telegram" : "email")

    if channel == "telegram" && user.telegram_chat_id.present?
      deliver_telegram(user, game)
    else
      deliver_email(user, game)
    end
  end

  def deliver_telegram(user, game)
    locale = Telegram::I18n.locale_for(user)
    formatter = Telegram::Helpers::GameFormatting
    game_url = "#{app_host}/games/#{game.id}"
    text = Telegram::I18n.t(
      :urgent_search_notification,
      locale: locale,
      id: game.id,
      owner: owner_label(game.user, locale),
      date: formatter.game_datetime(game, locale: locale) || "—",
      sport: formatter.sport_label(game.sport, locale: locale) || Telegram::I18n.t(:sport_any, locale: locale),
      skill: formatter.skill_level_label(game.skill_level, locale: locale),
      court: game.court&.name.to_s.presence || "—",
      url: game_url,
      notifications_url: notifications_url
    )

    SendTelegramNotificationJob.perform_later(user.telegram_chat_id, text, parse_mode: nil)
  end

  def notifications_url
    "#{app_host.to_s.delete_suffix('/')}/account/notifications"
  end

  def deliver_email(user, game)
    return false if user.email.blank? || user.telegram_generated_email?

    UserMailer.urgent_player_search(user, game).deliver_later
  end

  def owner_label(owner, locale)
    return "—" unless owner

    fallback = "#{Telegram::I18n.t(:user_fallback, locale: locale)} ##{owner.id}"
    Telegram::Helpers::UserLookup.display_name(owner, fallback: fallback)
  end

  def app_host
    ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
  end
end
