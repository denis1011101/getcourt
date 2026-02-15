module Telegram
  class PostGameStatsReminderJob < ApplicationJob
    queue_as :default

    def perform(game_id)
      game = Game.find_by(id: game_id)
      return unless game

      # For recurring games we need to enqueue the next occurrence reminder,
      # because no model update is guaranteed after the current reminder fires.
      game.schedule_post_game_stats_reminder if game.recurring?

      creator = game.user
      return unless creator&.telegram_chat_id

      host = ENV.fetch("APP_HOST", "http://localhost:3000")
      game_url = Rails.application.routes.url_helpers.game_url(game, host: host)
      signed = game.signed_id(expires_in: 7.days, purpose: "mark_not_happened")

      text = <<~MSG
        The game on #{game.date}#{game.time.present? ? " at #{game.time.strftime("%H:%M")}" : ""} has finished.
        Please fill in the statistics via Telegram.
        If it did not take place, press "Game did not happen".
      MSG

      Telegram::Api.send_with_buttons(
        creator.telegram_chat_id,
        text.strip,
        [
          { text: "Fill stats", callback_data: "tg_fill:#{game.id}" },
          # short id here — signed token is too long for callback_data
          { text: "Game did not happen", url: "#{game_url}?mark_not_happened=#{CGI.escape(signed)}" }
        ]
      )
    end
  end
end
