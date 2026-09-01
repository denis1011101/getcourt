class Game < ApplicationRecord
  after_commit :schedule_post_game_stats_reminder, on: %i[create update]
  after_commit :enqueue_urgent_player_search_notification, on: %i[create update]
  after_update :drop_training_plan_from_plain_game, if: -> { saved_change_to_kind? && !training? }
  after_update :remove_stale_coach_prebookings,
               if: -> { saved_change_to_coach_id? || saved_change_to_second_coach_id? || saved_change_to_date? || saved_change_to_recurring? }

  belongs_to :tournament, optional: true
  belongs_to :court
  belongs_to :user
  belongs_to :coach, class_name: "User", optional: true
  # У тренировки может быть второй тренер, у обычной игры тренеров нет вовсе.
  belongs_to :second_coach, class_name: "User", optional: true
  has_many :participations, dependent: :destroy
  has_many :prebookings, dependent: :destroy
  has_many :coach_prebookings, dependent: :destroy
  has_many :prebooking_cancellations, dependent: :destroy
  has_many :matches, dependent: :nullify
  # Событие с главной переживает удаление игры — просто теряет ссылку на неё.
  has_many :featured_matches, dependent: :nullify
  has_many :player_statistic_entries, dependent: :nullify
  has_many :game_media, class_name: "GameMedium", dependent: :destroy
  # План тренировки — блоки из библиотеки тренера в выбранном порядке.
  has_many :game_training_blocks, -> { ordered }, dependent: :destroy, inverse_of: :game
  has_many :training_blocks, through: :game_training_blocks
  # Правки плана, которые предложили участники тренировки.
  has_many :training_plan_proposals, dependent: :destroy

  SURFACES = Court::SURFACES
  KINDS = %w[game training].freeze
  ENVIRONMENTS = %w[indoor outdoor].freeze
  DEFAULT_PLAYERS = 4
  COACH_INVITATION_STATUSES = %w[pending accepted declined].freeze
  MAX_PREBOOKING_HORIZON = 52

  # A tournament game follows the tournament schedule, so the standalone game options don't apply.
  before_validation :drop_options_managed_by_tournament, if: -> { tournament_id.present? }
  before_validation :normalize_coach_assignment

  validates :date, presence: { message: "must be present" }
  validates :comment, length: { maximum: 500 }, allow_blank: true

  validates :players_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :surface, inclusion: { in: SURFACES }, allow_blank: true
  validates :environment, inclusion: { in: ENVIRONMENTS }, allow_blank: true
  validates :kind, inclusion: { in: KINDS }
  validates :coach_invitation_status, inclusion: { in: COACH_INVITATION_STATUSES }, allow_nil: true
  validates :second_coach_invitation_status, inclusion: { in: COACH_INVITATION_STATUSES }, allow_nil: true
  validate :selected_coaches_are_coaches
  validate :training_cannot_hide_recorded_scores, if: -> { persisted? && training? && kind_changed? }
  validate :prebooking_requires_recurring
  validate :surface_available_at_court
  validate :environment_available_at_court
  validate :within_tournament_dates_and_courts, if: -> { tournament.present? }

  def training?
    kind == "training"
  end

  def coaches
    [ coach, second_coach ].compact
  end

  # Чат игры живёт до конца дня игры. У повторяющейся игры одной даты нет,
  # поэтому там режим просто протухает через сутки, и его включают заново —
  # угадывать, какое занятие человек имел в виду, мы не беремся.
  CHAT_MAX_TTL = 24.hours

  def chat_open_until
    return CHAT_MAX_TTL.from_now if recurring? || date.blank?

    closes_at = date.end_of_day
    closes_at > Time.current ? closes_at : nil
  end

  def chat_open?
    chat_open_until.present?
  end

  # Кому уходит сообщение из чата: те же, кто выходит на корт, но только с
  # привязанным ботом — остальным доставить некуда.
  # NOT IN со списком, где есть NULL, в SQL не отбирает ничего — колонка
  # bigint, так что достаточно проверки на NULL.
  def chat_members
    User.where(id: team_member_ids).where.not(telegram_chat_id: nil)
  end

  # Игры, в чат которых человек вправе писать прямо сейчас.
  def self.with_open_chat_for(user)
    return none unless user

    participant_ids = Participation.approved.where(user_id: user.id).pluck(:game_id)
    coach_ids = where(coach_id: user.id, coach_invitation_status: "accepted").pluck(:id) +
                where(second_coach_id: user.id, second_coach_invitation_status: "accepted").pluck(:id)
    owned_ids = where(user_id: user.id).pluck(:id)

    where(id: (participant_ids + coach_ids + owned_ids).uniq)
      .includes(:court)
      .select(&:chat_open?)
  end

  # Кто выходит на корт: состав, принятые тренеры и организатор. Они же решают,
  # как пройдёт занятие — предлагают правки плана и голосуют за них.
  def team_member_ids
    ids = participations.approved.where.not(user_id: nil).pluck(:user_id)
    (ids + accepted_coaches.map(&:id) + [ user_id ]).compact.uniq
  end

  # Порядок блоков задаёт сам список: он и есть план занятия.
  def replace_training_plan!(block_ids)
    block_ids = Array(block_ids).map(&:to_i).uniq.reject(&:zero?)

    transaction do
      game_training_blocks.where.not(training_block_id: block_ids).destroy_all
      block_ids.each_with_index do |block_id, index|
        entry = game_training_blocks.find_or_initialize_by(training_block_id: block_id)
        entry.position = index
        entry.save!
      end
    end

    game_training_blocks.reset
    training_blocks.reset
  end

  def assigned_coach_ids
    [ coach_id, second_coach_id ].compact
  end

  # Каждый тренер отвечает на своё приглашение, поэтому статус ищем по слоту.
  def coach_slot_for(candidate)
    candidate_id = candidate.respond_to?(:id) ? candidate.id : candidate
    return nil if candidate_id.blank?

    if coach_id == candidate_id
      :coach
    elsif second_coach_id == candidate_id
      :second_coach
    end
  end

  def invitation_status_for(candidate)
    case coach_slot_for(candidate)
    when :coach then coach_invitation_status
    when :second_coach then second_coach_invitation_status
    end
  end

  def accepted_coach?(candidate)
    invitation_status_for(candidate) == "accepted"
  end

  def accepted_coaches
    coaches.select { |candidate| accepted_coach?(candidate) }
  end

  def coach_accepted?
    accepted_coaches.any?
  end

  def answer_coach_invitation!(candidate, status)
    slot = coach_slot_for(candidate)
    return false unless slot

    update!("#{slot}_invitation_status" => status)
  end

  # Is this date one of the game's occurrences? A recurring game repeats weekly
  # from its start date, a one-off game has exactly one.
  def occurrence_date?(candidate)
    return false if candidate.blank? || date.blank?

    candidate = candidate.to_date
    return candidate == date.to_date unless recurring?

    candidate >= date && ((candidate - date.to_date).to_i % 7).zero?
  end

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
    self.kind = "game"
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
        prebooking_horizon_dates(n)
      else
        [ date ].compact
      end

    Rails.logger.debug "[Game#ensure_prebookings_for_next_weeks] game_id=#{id} candidate_dates=#{dates.inspect} classes=#{dates.map(&:class).inspect} existing=#{prebookings.distinct.pluck(:date).map { |d| [ d, d.class ] }.inspect}"

    ensure_prebookings_for_dates(dates)
  end

  def ensure_prebookings_for_dates(dates)
    return unless prebooking_enabled?

    dates.each do |d|
      d = d.to_date
      next if cancelled_on?(d)
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
    if prev && prev < Date.current && should_reset_participations?
      return prev
    end

    return nd if nd >= Date.current

    prev || nd
  end


  def next_date
    d = date
    return nil unless d

    if recurring?
      # advance to first occurrence >= today
      d += 7 while d < Date.current

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

  def prebooking_horizon_dates(count = 3)
    return [] unless recurring?

    count = count.to_i.clamp(3, MAX_PREBOOKING_HORIZON)
    base = (next_date.presence || date).to_date
    Array.new(count) { |i| base + i.weeks }
  end

  # Возвращает даты в заданном горизонте и даты с существующими бронями/отменами.
  def prebooking_candidate_dates(count = 3)
    return [] unless recurring?

    horizon_dates = prebooking_horizon_dates(count)
    # Only from the current occurrence onwards: a long-lived weekly game accumulates
    # years of bookings and cancellations, and none of the past ones are bookable.
    from = horizon_dates.first
    booked_dates = prebookings.where.not(user_id: nil).where(date: from..).distinct.pluck(:date)
    cancelled_dates = prebooking_cancellations.where(date: from..).distinct.pluck(:date)
    coach_dates = coach_prebookings.where(date: from..).distinct.pluck(:date)

    (horizon_dates + booked_dates + cancelled_dates + coach_dates).compact.map(&:to_date).uniq.sort
  end

  # Сколько игроков нужно на игру (по умолчанию 4). Это же число — количество
  # слотов на дату в пребукинге.
  def required_players
    players_count.to_i > 0 ? players_count.to_i : DEFAULT_PLAYERS
  end
  alias_method :prebooking_required_players, :required_players

  # Занятые и свободные места. Считаем по уже загруженной ассоциации, если она
  # есть: список игр грузит participations через includes, и запрос на каждую
  # игру превратил бы страницу в N+1.
  def spots_taken
    if participations.loaded?
      participations.target.count(&:approved?)
    else
      participations.approved.count
    end
  end

  def spots_left
    required_players - spots_taken
  end

  def spots_available?
    spots_left.positive?
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

  # Сброс участий имеет смысл только когда предыдущее вхождение уже отыграно.
  # Без этой проверки серия, у которой первая игра ещё впереди, попадала под
  # ResetParticipationsJob в первую же ночь: маркер nil, next_date в будущем,
  # и состав вычищался за несколько дней до игры.
  def should_reset_participations?(as_of = Date.current)
    return false unless recurring?
    nd = next_date
    return false unless nd

    prev = previous_occurrence_before_next_date
    return false unless prev && prev < as_of

    last_participations_reset_at.nil? || last_participations_reset_at.to_date < nd
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

  # Описывает ли карточка игры то, что происходило в этот момент. У повторяющихся
  # игр запись живёт дальше своего вхождения: ResetParticipationsJob перебрасывает
  # её на следующую неделю и затирает состав, так что ссылки из прошлых циклов
  # ведут уже на чужую игру. Отсюда правило для всех «открыть игру» на сайте.
  def covers_moment?(timestamp)
    return false if timestamp.blank?

    cycle_start = current_cycle_start
    cycle_start.blank? || timestamp >= cycle_start
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

  def normalize_coach_assignment
    # Тренер бывает только у тренировки, так что игра с тренером ею и становится.
    self.kind = "training" if with_coach?

    unless with_coach?
      self.coach = nil
      self.second_coach = nil
      self.coach_invitation_status = nil
      self.second_coach_invitation_status = nil
      return
    end

    # Второй тренер без первого — это просто один тренер.
    self.coach, self.second_coach = second_coach, nil if coach_id.blank?
    self.second_coach = nil if second_coach_id.present? && second_coach_id == coach_id

    normalize_invitation_status :coach
    normalize_invitation_status :second_coach
  end

  def normalize_invitation_status(slot)
    if public_send("#{slot}_id").blank?
      public_send("#{slot}_invitation_status=", nil)
    elsif public_send("will_save_change_to_#{slot}_id?")
      public_send("#{slot}_invitation_status=", "pending")
    end
  end

  def drop_training_plan_from_plain_game
    # У обычной игры плана занятия не бывает, поэтому он уходит вместе с типом.
    game_training_blocks.destroy_all
  end

  # Счёт у тренировки не показать и не исправить, поэтому игру с уже записанными
  # матчами в тренировку не превращаем — иначе счёт остался бы висеть в статистике.
  def training_cannot_hide_recorded_scores
    errors.add(:kind, "cannot switch to training while the game has recorded scores") if matches.exists?
  end

  def selected_coaches_are_coaches
    coaches.each do |candidate|
      errors.add(:coach, "must be a coach") unless candidate.coach?
    end
  end

  # Coach bookings hang off concrete occurrences, so they go stale when the coach
  # changes, and also when the game moves to another date or stops repeating.
  def remove_stale_coach_prebookings
    coach_prebookings.where.not(coach_id: assigned_coach_ids).delete_all
    return unless saved_change_to_date? || saved_change_to_recurring?

    unless recurring? && date.present?
      coach_prebookings.delete_all
      return
    end

    stale_ids = coach_prebookings.reject { |booking| occurrence_date?(booking.date) }.map(&:id)
    coach_prebookings.where(id: stale_ids).delete_all if stale_ids.any?
  end

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
