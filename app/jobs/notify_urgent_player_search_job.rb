class NotifyUrgentPlayerSearchJob < ApplicationJob
  queue_as :default

  def perform(game_id)
    game = Game.includes(:court, :user).find_by(id: game_id)
    return unless game&.urgent_player_search?

    game_city = game.court&.city_name.to_s.strip.downcase
    return if game_city.blank?

    User.where(notify_nearby: true).where.not(id: game.user_id).find_each do |user|
      next unless user.city_name.to_s.strip.downcase == game_city

      deliver(user, game)
    end
  rescue => e
    Rails.logger.error "[NotifyUrgentPlayerSearchJob] #{e.class}: #{e.message}"
  end

  private

  def deliver(user, game)
    if user.notification_channel == "telegram" && user.telegram_chat_id.present?
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
      url: game_url
    )

    SendTelegramNotificationJob.perform_later(user.telegram_chat_id, text, parse_mode: nil)
  end

  def deliver_email(user, game)
    return false if user.telegram_generated_email?

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
