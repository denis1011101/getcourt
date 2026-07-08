module Telegram
  class ParticipationNotifier
    # action: :joined, :left, :removed, :guest_added
    def self.notify_owner(game, actor, action:)
      return unless game.user&.telegram_chat_id.present?

      locale = Telegram::Helpers::UserLookup.locale_for(game.user.telegram_chat_id)
      user_name = actor_name(actor, locale)
      date = game.respond_to?(:next_date) ? (game.next_date || game.date) : game.date
      time = game.respond_to?(:next_time) ? (game.next_time || game.time) : game.time
      date_str = date&.strftime("%Y-%m-%d")
      time_str = time&.strftime("%H:%M")
      host = ENV.fetch("APP_HOST", ENV.fetch("HOSTNAME", "https://getcourt.co"))
      game_url = "#{host}/games/#{game.id}"

      action_text = case action.to_sym
      when :joined then "joined your game"
      when :left   then "left your game"
      when :removed then "was removed from your game"
      when :guest_added then "was added to your game"
      else action.to_s
      end

      text = "#{user_name} #{action_text} on #{date_str} at #{time_str}\n\n#{game_url}"
      SendTelegramNotificationJob.perform_later(game.user.telegram_chat_id, text)
    end

    def self.actor_name(actor, locale)
      if actor.respond_to?(:guest?) && actor.guest?
        "#{actor.guest_name} (#{Telegram::I18n.t(:guest_badge, locale: locale)})"
      elsif actor.is_a?(String)
        actor
      else
        Telegram::Helpers::UserLookup.display_name(actor, fallback: "User ##{actor&.id}")
      end
    end
  end
end
