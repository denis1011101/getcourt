module Telegram
  class PostGameStatsReminderJob < ApplicationJob
    queue_as :default

    def perform(game_id)
      game = Game.find_by(id: game_id)
      return unless game

      reschedule_recurring_reminder(game) if game.recurring?

      return if stats_already_filled?(game)

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

    private

    def stats_already_filled?(game)
      cycle_start = game.respond_to?(:current_cycle_start) ? game.current_cycle_start : nil
      query = PlayerStatisticEntry.where(user_id: game.user_id, game_id: game.id)
      query = query.where("recorded_at >= ?", cycle_start) if cycle_start.present?
      query.exists?
    end

    def reschedule_recurring_reminder(game)
      reminder_at = next_recurring_reminder_at(game)
      return unless reminder_at && reminder_at > Time.current

      game.cancel_post_game_stats_reminder if game.post_game_stats_reminder_job_id.present?

      enqueued = Telegram::PostGameStatsReminderJob.set(wait_until: reminder_at).perform_later(game.id)
      jid = enqueued.respond_to?(:provider_job_id) ? enqueued.provider_job_id : (enqueued.respond_to?(:job_id) ? enqueued.job_id : nil)
      game.update_column(:post_game_stats_reminder_job_id, jid) if jid
    end

    def next_recurring_reminder_at(game)
      occurrence_date = game.next_date || game.date
      return unless occurrence_date

      max_iters = 520
      iter = 0

      while occurrence_date <= Date.today && iter < max_iters
        occurrence_date += 7
        iter += 1
      end

      while game.cancelled_on?(occurrence_date) && iter < max_iters
        occurrence_date += 7
        iter += 1
      end

      return if iter >= max_iters || game.cancelled_on?(occurrence_date)

      Time.use_zone(game.creator_time_zone) do
        hh = 0
        mm = 0

        t = game.time
        if t.respond_to?(:strftime)
          hh = t.strftime("%H").to_i
          mm = t.strftime("%M").to_i
        elsif t.present?
          parts = t.to_s.strip.split(":")
          hh = parts[0].to_i
          mm = parts[1].to_i
        end

        Time.zone.local(occurrence_date.year, occurrence_date.month, occurrence_date.day, hh, mm, 0) + 4.hours
      end
    rescue
      nil
    end
  end
end
