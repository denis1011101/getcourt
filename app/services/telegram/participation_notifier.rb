module Telegram
  class ParticipationNotifier
    # action: :joined, :left, :removed, :guest_added
    def self.notify_owner(game, actor, action:)
      return unless game.user&.telegram_chat_id.present?

      locale = Telegram::Helpers::UserLookup.locale_for(game.user.telegram_chat_id)
      user_name = actor_name(actor, locale)
      date = game.respond_to?(:next_date) ? (game.next_date || game.date) : game.date
      time = game.respond_to?(:next_time) ? (game.next_time || game.time) : game.time
      date_str = date ? ::I18n.l(date, format: :short, locale: locale) : "—"
      time_str = Telegram::Helpers::GameFormatting.format_time_hhmm(time, locale: locale) || "—:--"
      host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
      game_url = "#{host}/games/#{game.id}"

      action_text = case action.to_sym
      when :joined then Telegram::I18n.t(:participation_joined, locale: locale)
      when :left then Telegram::I18n.t(:participation_left, locale: locale)
      when :removed then Telegram::I18n.t(:participation_removed, locale: locale)
      when :guest_added then Telegram::I18n.t(:participation_guest_added, locale: locale)
      else action.to_s
      end

      text = Telegram::I18n.t(:participation_notification, locale: locale,
        name: user_name, action: action_text, date: date_str, time: time_str) + "\n\n#{game_url}"
      SendTelegramNotificationJob.perform_later(game.user.telegram_chat_id, text)
    end

    def self.actor_name(actor, locale)
      if actor.respond_to?(:guest?) && actor.guest?
        "#{actor.guest_name} (#{Telegram::I18n.t(:guest_badge, locale: locale)})"
      elsif actor.is_a?(String)
        actor
      else
        fallback = "#{Telegram::I18n.t(:user_fallback, locale: locale)} ##{actor&.id}"
        Telegram::Helpers::UserLookup.display_name(actor, fallback: fallback)
      end
    end
  end
end
