module Telegram
  class PostGameStatsReminderJob < ApplicationJob
    queue_as :default

    def perform(game_id)
      game = Game.find_by(id: game_id)
      return unless game
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
          { text: "Fill in Telegram", callback_data: "tg_fill:#{game.id}" },
          # short id here — signed token is too long for callback_data
          { text: "Game did not happen", callback_data: "tg_not_happened:#{game.id}" }
        ]
      )
    end
  end
end
