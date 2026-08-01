module Telegram
  class ParticipationNotifier
    # action: :joined, :left, :removed, :guest_added
    def self.notify_owner(game, actor, action:)
      return unless game.user

      locale = Telegram::I18n.locale_for(game.user)
      user_name = actor_name(actor, locale)
      date = game.respond_to?(:next_date) ? (game.next_date || game.date) : game.date
      time = game.respond_to?(:next_time) ? (game.next_time || game.time) : game.time
      date_str = date ? ::I18n.l(date, format: :telegram, locale: locale) : "—"
      time_str = Telegram::Helpers::GameFormatting.format_time_hhmm(time, locale: locale) || "—:--"
      host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
      game_url = "#{host}/games/#{game.id}"

      action_text = case action.to_sym
      when :requested then Telegram::I18n.t(:participation_requested, locale: locale)
      when :joined then Telegram::I18n.t(:participation_joined, locale: locale)
      when :left then Telegram::I18n.t(:participation_left, locale: locale)
      when :removed then Telegram::I18n.t(:participation_removed, locale: locale)
      when :guest_added then Telegram::I18n.t(:participation_guest_added, locale: locale)
      else action.to_s
      end

      telegram_text = Telegram::I18n.t(:participation_notification, locale: locale,
        name: user_name, action: action_text, date: date_str, time: time_str) + "\n\n#{game_url}"

      email_subject, email_body, action_label = email_content(game.user, user_name, action, date, time, game.id)
      NotificationDelivery.deliver(
        user: game.user,
        telegram_text: telegram_text,
        email_subject: email_subject,
        email_body: email_body,
        actions: [ { label: action_label, url: game_url } ]
      )
    end

    def self.email_content(owner, user_name, action, date, time, game_id)
      ::I18n.with_locale(NotificationDelivery.email_locale(owner)) do
        action_text = ::I18n.t("user_mailer.notification.participation_actions.#{action}")
        body = ::I18n.t("user_mailer.notification.participation_body",
          name: user_name,
          action: action_text,
          date: date ? ::I18n.l(date, format: :long) : "—",
          time: time&.strftime("%H:%M") || "—:--")

        [
          ::I18n.t("user_mailer.notification.participation_subject", game_id: game_id),
          body,
          ::I18n.t("user_mailer.notification.view_game")
        ]
      end
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
