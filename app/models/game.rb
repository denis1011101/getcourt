class Game < ApplicationRecord
  after_commit :schedule_post_game_stats_reminder, on: %i[create update]

  belongs_to :court
  belongs_to :user
  has_many :participations, dependent: :destroy
  has_many :prebookings, dependent: :destroy
  has_many :prebooking_cancellations, dependent: :destroy

  validates :date, presence: { message: "must be present" }

  validates :players_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :prebooking_requires_recurring

  # Schedule reminder for (game_datetime + 3.hours). Cancels previous scheduled if present.
  def schedule_post_game_stats_reminder
    t = scheduled_post_game_stats_reminder_time
    return unless t && t > Time.zone.now

    cancel_post_game_stats_reminder if post_game_stats_reminder_job_id.present?

    enqueued = Telegram::PostGameStatsReminderJob.set(wait_until: t).perform_later(id)
    jid = enqueued.respond_to?(:provider_job_id) ? enqueued.provider_job_id : (enqueued.respond_to?(:job_id) ? enqueued.job_id : nil)
    update_column(:post_game_stats_reminder_job_id, jid) if jid
  end

  # Try to remove previously scheduled job for SolidQueue (fall back to several possible APIs).
  def cancel_post_game_stats_reminder
    jid = post_game_stats_reminder_job_id
    return unless jid

    adapter = Rails.application.config.active_job.queue_adapter

    begin
      # SolidQueue common attempts
      if adapter == :solid_queue || adapter.to_s.downcase.include?("solid")
        # try repository API
        if defined?(SolidQueue::Repository) && SolidQueue::Repository.respond_to?(:delete)
          SolidQueue::Repository.delete(jid) rescue nil
        end

        # try job model
        if defined?(SolidQueue::Job) && SolidQueue::Job.respond_to?(:find_by)
          SolidQueue::Job.find_by(id: jid)&.destroy
        end

        # try top-level delete
        if defined?(SolidQueue) && SolidQueue.respond_to?(:delete)
          SolidQueue.delete(jid) rescue nil
        end
      end
    rescue => _e
      # noop
    end

    update_column(:post_game_stats_reminder_job_id, nil)
  end

  def scheduled_post_game_stats_reminder_time
    return nil unless date.present?

    d = next_date || date
    return nil unless d.present?

    begin
      if time.respond_to?(:hour)
        scheduled = Time.zone.local(d.year, d.month, d.day, time.hour, time.min)
      else
        parts = time.to_s.split(":")
        scheduled = Time.zone.local(d.year, d.month, d.day, parts[0].to_i, parts[1].to_i)
      end
    rescue
      scheduled = Time.zone.local(d.year, d.month, d.day, 23, 59)
    end

    scheduled + 3.hours
  end

  def prebooking_requires_recurring
    if prebooking_enabled? && !recurring?
      errors.add(:prebooking_enabled, "can be enabled only for repeating (weekly) games")
    end
  end

  # return true if prebookings behaviour is enabled for this game
  def prebooking_enabled?
    if respond_to?(:prebooking) # legacy/possible boolean column :prebooking
      !!self.prebooking
    elsif respond_to?(:prebooking_enabled) # alternative column name
      !!self.prebooking_enabled
    else
      prebookings.exists?
    end
  end

  # Ensure prebooking slots exist for next n occurrences (default 4)
  def ensure_prebookings_for_next_weeks(n = 4)
    return unless prebooking_enabled?

    dates = []
    if recurring?
      d = next_date || date
      while dates.size < n
        dates << d
        d += 7
      end
    else
      dates << date if date.present?
    end

    # create slots for each date and slot index up to players_count
    dates.each do |d|
      (1..(players_count.to_i > 0 ? players_count.to_i : 4)).each do |slot|
        prebookings.find_or_create_by!(date: d, slot_index: slot)
      end
    end
  end

  def date
    d = read_attribute(:date)
    begin
      Date.parse(d.to_s) if d.present?
    rescue
      nil
    end
  end

  def time
    read_attribute(:time)
  end

  # Choose which occurrence to show on the game page:
  # - if next_date is today or in the future => show next_date
  # - otherwise => show previous occurrence (if any), fallback to next_date
  def display_date_for_show
    nd = next_date
    return date unless nd
    return nd if nd >= Date.today

    previous_occurrence_before_next_date || nd
  end

  def next_date
    d = date
    return nil unless d

    if recurring?
      # advance to first occurrence >= today
      d += 7 while d < Date.today

      # skip cancelled occurrences
      max_iters = 520 # safety cap (~10 years)
      iter = 0
      while prebooking_cancellations.exists?(date: d) && iter < max_iters
        d += 7
        iter += 1
      end

      return nil if prebooking_cancellations.exists?(date: d) # all skipped
      d
    else
      return nil if prebooking_cancellations.exists?(date: d)
      d
    end
  end

  def next_time
    time
  end

  def previous_occurrence_before_next_date
    return nil unless recurring? && next_date.present?

    prev = next_date - 7
    max_iters = 520
    iter = 0
    while prebooking_cancellations.exists?(date: prev) && iter < max_iters
      prev -= 7
      iter += 1
    end

    return nil if prebooking_cancellations.exists?(date: prev)
    return nil if date.present? && prev < date

    prev
  end

  def should_reset_participations?(as_of = Date.today)
    return false unless recurring?
    nd = next_date
    return false unless nd
    last_participations_reset_at.nil? || last_participations_reset_at < nd
  end

  def mark_participations_reset!(date = next_date)
    update_column(:last_participations_reset_at, date)
  end
end
