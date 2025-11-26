module Telegram
  class ParticipationNotifier
    # action: :joined, :left, :removed
    def self.notify_owner(game, actor, action:)
      return unless game.user&.telegram_chat_id.present?

      user_name = actor&.name.presence || actor&.email || "User ##{actor.id}"
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
                    else action.to_s
                    end

      text = "#{user_name} #{action_text} on #{date_str} at #{time_str}\n#{game_url}"
      SendTelegramNotificationJob.perform_later(game.user.telegram_chat_id, text)
    end
  end
end
