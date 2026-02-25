class NotifyUrgentPlayerSearchJob < ApplicationJob
  queue_as :default

  def perform(game_id)
    game = Game.includes(:court, :user).find_by(id: game_id)
    return unless game&.urgent_player_search?

    game_city = game.court&.city_name.to_s.strip.downcase
    date = Telegram::Helpers::GameFormatting.game_datetime(game) || "—"
    sport = game.respond_to?(:sport) ? game.sport.to_s.presence : nil
    skill = game.respond_to?(:skill_level) ? game.skill_level.to_s.presence : nil
    court = game.court&.name.to_s.presence || "—"
    owner = owner_label(game.user)

    recipients = User.where(notify_nearby: true)
                     .where.not(id: game.user_id)
                     .where.not(telegram_chat_id: nil)

    recipients.find_each do |user|
      next if game_city.present? && user.city_name.present? && user.city_name.to_s.strip.downcase != game_city

      locale = (user.telegram_locale.presence || Telegram::I18n::DEFAULT_LOCALE).to_s
      text = Telegram::I18n.t(
        :urgent_search_notification,
        locale: locale,
        id: game.id,
        owner: owner,
        date: date,
        sport: sport || fallback(locale, "sport"),
        skill: (skill&.titleize || fallback(locale, "level")),
        court: court
      )

      SendTelegramNotificationJob.perform_later(user.telegram_chat_id, text, parse_mode: nil)
    end
  rescue => e
    Rails.logger.error "[NotifyUrgentPlayerSearchJob] #{e.class}: #{e.message}"
  end

  private

  def owner_label(owner)
    return "—" unless owner
    return "@#{owner.telegram_username.delete_prefix('@')}" if owner.telegram_username.present?
    owner.name.presence || owner.email.presence || "User ##{owner.id}"
  end

  def fallback(locale, type)
    return "any" if locale.start_with?("en")
    return "any" if type == "level"
    "any"
  end
end
