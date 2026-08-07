class PostGameStatsReminderJob < ApplicationJob
  queue_as :default

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    reschedule_recurring_reminder(game) if game.recurring?
    return if stats_already_filled?(game)

    creator = game.user
    return unless creator

    game_url = Rails.application.routes.url_helpers.game_url(game, host: app_host)
    signed = game.signed_id(expires_in: 7.days, purpose: "mark_not_happened")
    not_happened_url = "#{game_url}?mark_not_happened=#{CGI.escape(signed)}"
    notification = NotificationDelivery::Notification.new(
      subject: ->(locale) { I18n.t("user_mailer.notification.stats_subject", locale: locale) },
      body: ->(locale) { reminder_text(game, locale, game_url) },
      actions: ->(locale) { reminder_actions(locale, game_url, not_happened_url) }
    )

    NotificationDelivery.deliver(user: creator, notification: notification)
  end

  private

  def reminder_text(game, locale, game_url)
    datetime = [
      I18n.l(game.date, format: :telegram, locale: locale),
      Telegram::Helpers::GameFormatting.format_time_hhmm(game.time, locale: locale)
    ].compact.join(" ")
    text = Telegram::I18n.t(:post_game_stats_reminder, locale: locale, datetime: datetime)
    "#{text}\n\n#{game_url}"
  end

  def reminder_actions(locale, game_url, not_happened_url)
    [
      { label: Telegram::I18n.t(:fill_stats, locale: locale), url: game_url },
      { label: Telegram::I18n.t(:game_did_not_happen, locale: locale), url: not_happened_url }
    ]
  end

  def app_host
    ENV.fetch("APP_HOST", "http://localhost:3000")
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

    enqueued = PostGameStatsReminderJob.set(wait_until: reminder_at).perform_later(game.id)
    jid = if enqueued.respond_to?(:provider_job_id)
      enqueued.provider_job_id
    elsif enqueued.respond_to?(:job_id)
      enqueued.job_id
    end
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
      hour = 0
      minute = 0
      time = game.time
      if time.respond_to?(:strftime)
        hour = time.strftime("%H").to_i
        minute = time.strftime("%M").to_i
      elsif time.present?
        parts = time.to_s.strip.split(":")
        hour = parts[0].to_i
        minute = parts[1].to_i
      end

      Time.zone.local(occurrence_date.year, occurrence_date.month, occurrence_date.day, hour, minute, 0) + 4.hours
    end
  rescue
    nil
  end
end
