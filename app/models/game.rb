class Game < ApplicationRecord
  after_commit :schedule_post_game_stats_reminder, on: %i[create update]
  after_commit :enqueue_urgent_player_search_notification, on: %i[create update]

  belongs_to :tournament, optional: true
  belongs_to :court
  belongs_to :user
  has_many :participations, dependent: :destroy
  has_many :prebookings, dependent: :destroy
  has_many :prebooking_cancellations, dependent: :destroy
  has_many :matches, dependent: :nullify
  has_many :player_statistic_entries, dependent: :nullify

  SURFACES = Court::SURFACES
  ENVIRONMENTS = %w[indoor outdoor].freeze

  # A tournament game follows the tournament schedule, so the standalone game options don't apply.
  before_validation :drop_options_managed_by_tournament, if: -> { tournament_id.present? }

  validates :date, presence: { message: "must be present" }
  validates :comment, length: { maximum: 500 }, allow_blank: true

  validates :players_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :surface, inclusion: { in: SURFACES }, allow_blank: true
  validates :environment, inclusion: { in: ENVIRONMENTS }, allow_blank: true
  validate :prebooking_requires_recurring
  validate :surface_available_at_court
  validate :environment_available_at_court
  validate :within_tournament_dates_and_courts, if: -> { tournament.present? }

  def tournament_game?
    tournament_id.present?
  end

  def surface_label
    return nil if surface.blank?

    I18n.t("courts.surfaces.#{surface}", default: surface.to_s.tr("_", " ").capitalize)
  end

  def environment_label
    return nil if environment.blank?

    I18n.t("courts.index.#{environment}_badge", default: environment.to_s.capitalize)
  end

  # Проверяет наличие отмены в памяти, если данные загружены, иначе делает запрос.
  def cancelled_on?(d)
    if prebooking_cancellations.loaded?
      # Ищем в массиве в памяти
      prebooking_cancellations.target.any? { |c| c.date == d }
    else
      # Делаем запрос в БД
      prebooking_cancellations.exists?(date: d)
    end
  end

  # Schedule reminder for (game_datetime + 4.hours). Cancels previous scheduled if present.
  def schedule_post_game_stats_reminder
    t = scheduled_post_game_stats_reminder_time
    return unless t && t > Time.current

    cancel_post_game_stats_reminder if post_game_stats_reminder_job_id.present?

    enqueued = PostGameStatsReminderJob.set(wait_until: t).perform_later(id)
    jid = enqueued.respond_to?(:provider_job_id) ? enqueued.provider_job_id : (enqueued.respond_to?(:job_id) ? enqueued.job_id : nil)
    update_column(:post_game_stats_reminder_job_id, jid) if jid
  end

  def scheduled_post_game_stats_reminder_time
    d = next_date || date
    return nil unless d.present?

    Time.use_zone(creator_time_zone) do
      hh = 0
      mm = 0

      t = time
      if t.respond_to?(:strftime)
        hh = t.strftime("%H").to_i
        mm = t.strftime("%M").to_i
      elsif t.present?
        parts = t.to_s.strip.split(":")
        hh = parts[0].to_i
        mm = parts[1].to_i
      end

      start_at = Time.zone.local(d.year, d.month, d.day, hh, mm, 0)
      start_at + 4.hours
    end
  rescue
    nil
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

  def prebooking_requires_recurring
    if prebooking_enabled? && !recurring?
      errors.add(:prebooking_enabled, "can be enabled only for repeating (weekly) games")
    end
  end

  # Покрытие игры должно быть среди покрытий выбранного корта
  def surface_available_at_court
    return if surface.blank? || court.blank?
    return if court.surfaces.include?(surface)

    errors.add(:surface, "is not available at the selected court")
  end

  # Среда (indoor/outdoor) должна быть доступна на выбранном корте
  def environment_available_at_court
    return if environment.blank? || court.blank?
    return if court.environments.include?(environment)

    errors.add(:environment, "is not available at the selected court")
  end

  # Игра турнира проходит в даты и на кортах, заданных турниром
  def within_tournament_dates_and_courts
    unless tournament.covers?(date)
      errors.add(:date, "must be within the tournament dates")
    end

    tournament_court_ids = tournament.court_ids
    if court_id.present? && tournament_court_ids.any? && tournament_court_ids.exclude?(court_id)
      errors.add(:court_id, "must be one of the tournament courts")
    end
  end

  def drop_options_managed_by_tournament
    self.recurring = false
    self.prebooking_enabled = false
    self.with_coach = false
    self.urgent_player_search = false
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

    dates =
      if recurring?
        prebooking_candidate_dates(n)
      else
        [ date ].compact
      end

    Rails.logger.debug "[Game#ensure_prebookings_for_next_weeks] game_id=#{id} candidate_dates=#{dates.inspect} classes=#{dates.map(&:class).inspect} existing=#{prebookings.distinct.pluck(:date).map { |d| [ d, d.class ] }.inspect}"

    dates.each do |d|
      d = d.to_date
      (1..prebooking_required_players).each do |slot|
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
  # - if previous occurrence already passed and participations haven't been reset => show prev
  # - if next_date is today or in the future => show next_date
  # - otherwise => show previous occurrence (if any), fallback to next_date
  def display_date_for_show
    nd = next_date
    return date unless nd

    prev = previous_occurrence_before_next_date

    # if participations were reset for the previous occurrence, show that one
    if prev && last_participations_reset_at.present? && last_participations_reset_at.to_date == prev
      return prev
    end

    # if previous occurrence already passed but participations haven't been
    # reset yet, we're still in that occurrence's cycle (stats should stay unlocked)
    if prev && prev < Date.today && should_reset_participations?
      return prev
    end

    return nd if nd >= Date.today

    prev || nd
  end


  def next_date
    d = date
    return nil unless d

    if recurring?
      # advance to first occurrence >= today
      d += 7 while d < Date.today

      # skip cancelled occurrences
      max_iters = 520
      iter = 0

      # ОПТИМИЗАЦИЯ: используем cancelled_on? вместо prebooking_cancellations.exists?
      while cancelled_on?(d) && iter < max_iters
        d += 7
        iter += 1
      end

      return nil if cancelled_on?(d) # all skipped
      d
    else
      return nil if cancelled_on?(d)
      d
    end
  end

  # Возвращает массив дат-кандидатов для предварительной записи (Date), по умолчанию 3 даты
  def prebooking_candidate_dates(count = 3)
    return [] unless recurring?
    display_date = (next_date.presence || date).to_date
    candidates = []
    candidates << next_date.to_date if next_date.present?
    candidates << (display_date + 7)            # keep Date arithmetic
    base = candidates.find { |d| d > display_date } || (display_date + 7)
    Array.new(count) { |i| base + i * 7 }       # produce Date objects
  end

  # Сколько слотов требуется на дату (по умолчанию 4)
  def prebooking_required_players
    players_count.to_i > 0 ? players_count.to_i : 4
  end

  def next_time
    time
  end

  def previous_occurrence_before_next_date
    return nil unless recurring? && next_date.present?

    prev = next_date - 7
    max_iters = 520
    iter = 0

    # ОПТИМИЗАЦИЯ: используем cancelled_on?
    while cancelled_on?(prev) && iter < max_iters
      prev -= 7
      iter += 1
    end

    return nil if cancelled_on?(prev)
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

  # Начало текущего игрового цикла (для фильтрации матчей/записей статистики).
  # Использует display_date_for_show вместо last_participations_reset_at,
  # т.к. reset может сдвинуться раньше отображаемого вхождения.
  def current_cycle_start
    display_date_for_show&.beginning_of_day
  end

  # Таймзона создателя (или дефолт приложения)
  def creator_time_zone
    tz = user&.timezone_or_default if respond_to?(:user)
    tz = tz.presence
    tz || Time.zone.name
  rescue
    Time.zone.name
  end

  # Старт игры в таймзоне создателя (или переданной).
  # Логика "occurrence" как в UI: display_date_for_show -> next_date -> date, время: next_time -> time.
  # Если время отсутствует — считаем стартом начало дня.
  def start_at_for_ui(time_zone: creator_time_zone)
    Time.use_zone(time_zone) do
      start_at_for_ui_in_current_zone
    end
  rescue
    nil
  end

  def started_for_ui?(now: nil, time_zone: creator_time_zone)
    Time.use_zone(time_zone) do
      now ||= Time.zone.now
      start_at = start_at_for_ui_in_current_zone
      start_at ? (now >= start_at) : false
    end
  rescue
    false
  end

  def urgent_player_search?
    !!self[:urgent_player_search]
  end

  private

  def enqueue_urgent_player_search_notification
    return unless urgent_player_search?
    return unless saved_change_to_urgent_player_search?
    return unless self[:urgent_player_search]

    NotifyUrgentPlayerSearchJob.perform_later(id)
  end

  # IMPORTANT: relies on Time.zone being already set (caller wraps Time.use_zone)
  def start_at_for_ui_in_current_zone
    d =
      if respond_to?(:display_date_for_show)
        display_date_for_show
      elsif respond_to?(:next_date)
        next_date
      elsif respond_to?(:date)
        date
      end
    return nil unless d.present?

    t =
      if respond_to?(:next_time)
        next_time
      elsif respond_to?(:time)
        time
      end

    date =
      if d.respond_to?(:to_date)
        d.to_date
      else
        Date.parse(d.to_s) rescue nil
      end
    return nil unless date

    hh = 0
    mm = 0

    if t.respond_to?(:strftime)
      hh = t.strftime("%H").to_i
      mm = t.strftime("%M").to_i
    else
      s = t.to_s.strip
      if s.include?(":")
        parts = s.split(":")
        hh = parts[0].to_i
        mm = parts[1].to_i
      end
    end

    Time.zone.local(date.year, date.month, date.day, hh, mm, 0)
  end
end
