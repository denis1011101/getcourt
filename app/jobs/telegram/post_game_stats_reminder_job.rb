module Telegram
  class PostGameStatsReminderJob < ApplicationJob
    queue_as :default

    def perform(game_id)
      game = Game.find_by(id: game_id)
      return unless game

      reschedule_recurring_reminder(game) if game.recurring?

      return if stats_already_filled?(game)

      creator = game.user
      return unless creator

      host = ENV.fetch("APP_HOST", "http://localhost:3000")
      game_url = Rails.application.routes.url_helpers.game_url(game, host: host)
      signed = game.signed_id(expires_in: 7.days, purpose: "mark_not_happened")
      not_happened_url = "#{game_url}?mark_not_happened=#{CGI.escape(signed)}"
      locale = Telegram::I18n.locale_for(creator)
      datetime = [
        ::I18n.l(game.date, format: :telegram, locale: locale),
        Telegram::Helpers::GameFormatting.format_time_hhmm(game.time, locale: locale)
      ].compact.join(" ")
      telegram_text = Telegram::I18n.t(:post_game_stats_reminder, locale: locale, datetime: datetime)
      telegram_buttons = [
        [ { text: Telegram::I18n.t(:fill_stats, locale: locale), url: game_url } ],
        [ { text: Telegram::I18n.t(:game_did_not_happen, locale: locale), url: not_happened_url } ]
      ]

      email_subject, email_body, fill_label, not_happened_label = email_content(creator, game)

      NotificationDelivery.deliver(
        user: creator,
        telegram_text: telegram_text,
        email_subject: email_subject,
        email_body: email_body,
        actions: [
          { label: fill_label, url: game_url },
          { label: not_happened_label, url: not_happened_url }
        ],
        telegram_buttons: telegram_buttons
      )
    end

    private

    def email_content(creator, game)
      ::I18n.with_locale(NotificationDelivery.email_locale(creator)) do
        datetime = [ ::I18n.l(game.date, format: :long), game.time&.strftime("%H:%M") ].compact.join(" ")
        [
          ::I18n.t("user_mailer.notification.stats_subject"),
          ::I18n.t("user_mailer.notification.stats_body", datetime: datetime),
          ::I18n.t("user_mailer.notification.fill_stats"),
          ::I18n.t("user_mailer.notification.game_did_not_happen")
        ]
      end
    end

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
