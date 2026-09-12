class Game < ApplicationRecord
  # Дни недели, по которым идёт серия: [1, 4] — понедельник и четверг.
  serialize :recurrence_days, coder: JSON, type: Array
  # Сами отмеченные в календаре даты: они и есть расписание, а галки повтора
  # только продолжают его за последней из них.
  serialize :occurrence_dates, coder: JSON, type: Array

  after_commit :schedule_post_game_stats_reminder, on: %i[create update]
  after_commit :announce_urgent_player_search, on: %i[create update]
  after_update :drop_training_plan_from_plain_game, if: -> { saved_change_to_kind? && !training? }
  after_update :remove_stale_bookings,
               if: -> { saved_change_to_coach_id? || saved_change_to_second_coach_id? || saved_change_to_date? ||
                        saved_change_to_recurring? || saved_change_to_recurring_monthly? ||
                        saved_change_to_recurrence_days? || saved_change_to_occurrence_dates? }

  belongs_to :tournament, optional: true
  # Корт можно оставить «пока не выбран»: игру часто объявляют раньше, чем знают,
  # где она пройдёт. Всё, что от корта зависит (город, карта, погода, поиск
  # игроков), просто ждёт, пока его выберут.
  belongs_to :court, optional: true
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

  # Игры, которые ещё впереди: бесконечная серия — всегда, конечная — пока не
  # прошла её последняя отметка. Списки и уборка спрашивают именно это, а не
  # одну галку недельного повтора.
  # Что можно показывать наружу (API, MCP): корты на модерации скрыты, а игра,
  # у которой корт ещё не выбран, — обычная и видна. NULL в moderation_status
  # берётся из LEFT JOIN — у самого корта он NOT NULL.
  scope :publicly_visible, -> {
    left_outer_joins(:court).where(courts: { moderation_status: [ nil, "approved" ] })
  }
  scope :still_running, ->(day = Date.current) {
    # ends_on проставляет колбэк, поэтому у записей, заведённых мимо него
    # (фикстуры, ручные вставки), его нет — для них спрашиваем саму дату.
    where(recurring: true)
      .or(where(recurring_monthly: true))
      .or(where(ends_on: day..))
      .or(where(ends_on: nil).where(date: day..))
  }
  scope :series, -> {
    where(recurring: true).or(where(recurring_monthly: true)).or(where.not(occurrence_dates: [ nil, "[]" ]))
  }

  SURFACES = Court::SURFACES
  KINDS = %w[game training].freeze
  ENVIRONMENTS = %w[indoor outdoor].freeze
  DEFAULT_PLAYERS = 4
  COACH_INVITATION_STATUSES = %w[pending accepted declined].freeze
  MAX_PREBOOKING_HORIZON = 52
  # Год поисков вперёд или назад: дальше расписание уже не ищем.
  MAX_OCCURRENCE_SEARCH_DAYS = 400

  # A tournament game follows the tournament schedule, so the standalone game options don't apply.
  before_validation :drop_options_managed_by_tournament, if: -> { tournament_id.present? }
  before_validation :normalize_coach_assignment
  before_validation :normalize_recurrence_days
  before_save :remember_last_occurrence

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
  validate :court_chosen_for_player_search
  validate :players_count_chosen_for_prebooking
  validate :within_tournament_dates_and_courts, if: -> { tournament.present? }

  def training?
    kind == "training"
  end

  def coaches
    [ coach, second_coach ].compact
  end

  # Цикл занятия — что и когда сменяется при сбросе состава — живёт в
  # Game::OccurrenceCycle: одна граница отвечает и карточке, и напоминаниям, и
  # чату, и самой задаче сброса.
  def occurrence_cycle
    @occurrence_cycle ||= OccurrenceCycle.new(self)
  end

  def chat_open_until
    occurrence_cycle.chat_open_until
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

  # Календарь формы отдаёт дни строкой, а телеграм-флоу — массивом: нормализуем
  # на входе, чтобы читатель всегда получал числа 0..6 без дублей.
  def recurrence_days=(value)
    days = value.is_a?(String) ? value.split(",") : Array(value)
    super(days.filter_map { |day| Integer(day.to_s.strip, exception: false) }.select { |day| (0..6).cover?(day) }.uniq.sort)
  end

  # Пустое правило значит «те же дни недели, что у отмеченных дат»: у серий,
  # заведённых до календаря, отметка одна — день их даты, как и было.
  def recurrence_weekdays
    days = Array(recurrence_days).map(&:to_i).select { |day| (0..6).cover?(day) }.uniq.sort
    days.presence || scheduled_dates.map(&:wday).uniq.sort
  end

  # Расписание игры — это отмеченные в календаре даты. У записей, заведённых до
  # календаря, отмеченных дат нет: их расписание — одна дата игры, дальше по
  # галке повтора.
  def scheduled_dates
    dates = Array(occurrence_dates).filter_map { |value| value.to_date rescue nil }.uniq.sort
    dates.presence || Array(date)
  end

  # Серия — игра, у которой занятий больше одного: несколько отмеченных дат или
  # повтор за последней из них. По этому же признаку живут состав, чат и
  # предзапись, поэтому спрашивать надо его, а не одну галку недельного повтора.
  def series?
    recurring? || recurring_monthly? || scheduled_dates.many?
  end

  # Даты, которыми расписание показывается в календаре формы. У серий,
  # заведённых до календаря, отмеченных дат нет — разворачиваем их расписание в
  # по одной дате на каждый день недели, иначе правка формы схлопнула бы серию
  # «пн + чт» до одних понедельников.
  def recurrence_seed_dates
    return scheduled_dates.compact if occurrence_dates.present?
    return Array(date) unless recurring? && date.present?

    recurrence_weekdays.map { |wday| date + ((wday - date.wday) % 7) }.sort
  end

  # Числа месяца, по которым идёт ежемесячный повтор: 7-е и 21-е — [7, 21].
  def recurrence_month_days
    scheduled_dates.map(&:day).uniq.sort
  end

  # Занятие ли это? Отмеченные даты — всегда, а за последней из них расписание
  # продолжают галки: еженедельно по тем же дням недели, ежемесячно по тем же
  # числам.
  def occurrence_date?(candidate)
    return false if candidate.blank? || date.blank?

    candidate = candidate.to_date
    return true if scheduled_dates.include?(candidate)

    candidate > scheduled_dates.last && repeats_on?(candidate)
  end

  # Продолжает ли расписание эту дату за своей последней отметкой.
  def repeats_on?(candidate)
    return true if recurring? && recurrence_weekdays.include?(candidate.wday)

    recurring_monthly? && recurrence_month_days.include?(candidate.day)
  end

  def tournament_game?
    tournament_id.present?
  end

  # Имя корта для заголовков и карточек; пока корт не выбран — так и пишем.
  def court_name
    court&.name.presence || I18n.t("games.court_pending")
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

  # Расписание живёт только у серии. И если дату перенесли мимо расписания —
  # например, из телеграм-бота, где выбирают один день, — старые дни недели уже
  # не про эту серию: оставляем день новой даты.
  def normalize_recurrence_days
    if date.present?
      # Дату переносят и из телеграм-бота, где выбирают один день: расписание,
      # оставшееся от календаря, там уже не про эту серию.
      self.occurrence_dates = [] if occurrence_dates.present? && scheduled_dates.exclude?(date)
      self.occurrence_dates = recurrence_seed_dates.compact.map(&:to_s) if occurrence_dates.blank?
    end

    if !recurring?
      self.recurrence_days = []
    elsif date.present? && recurrence_days.present? && recurrence_days.exclude?(date.wday)
      self.recurrence_days = [ date.wday ]
    end
  end

  # Последнее занятие конечной серии: по нему списки и уборка понимают, что она
  # отыграна. У бесконечной его нет.
  def remember_last_occurrence
    self.ends_on = (recurring? || recurring_monthly?) ? nil : scheduled_dates.last
  end

  def prebooking_requires_recurring
    if prebooking_enabled? && !series?
      errors.add(:prebooking_enabled, "can be enabled only for repeating (weekly) games")
    end
  end

  # Слоты пребукинга — это ровно players_count штук на дату; без числа игроков
  # раздавать нечего.
  def players_count_chosen_for_prebooking
    return unless prebooking_enabled? && !players_count_chosen?

    errors.add(:prebooking_enabled, :players_count_required)
  end

  # Покрытие игры должно быть среди покрытий выбранного корта
  def surface_available_at_court
    return if surface.blank? || court.blank?
    return if court.surfaces.include?(surface)

    errors.add(:surface, "is not available at the selected court")
  end

  # Среда (indoor/outdoor) должна быть доступна на выбранном корте
  # Поиск игроков рассылается по городу корта и рисует карточку с адресом —
  # без корта ни того, ни другого не будет, так что и объявлять нечего.
  def court_chosen_for_player_search
    return unless urgent_player_search? && court_id.blank?

    errors.add(:urgent_player_search, :court_required)
  end

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
    self.recurring_monthly = false
    self.recurrence_days = []
    self.occurrence_dates = []
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
      if series?
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

  # Карточка показывает то занятие, которому принадлежит нынешний состав: пока
  # сброс не прошёл — уже отыгранное, после — ближайшее.
  def display_date_for_show
    occurrence_cycle.roster_occurrence
  end


  def next_date
    d = date
    return nil unless d

    if series?
      # advance to first occurrence >= today
      d = occurrence_on_or_after(Date.current)

      # skip cancelled occurrences
      max_iters = 520
      iter = 0

      # ОПТИМИЗАЦИЯ: используем cancelled_on? вместо prebooking_cancellations.exists?
      while cancelled_on?(d) && iter < max_iters
        d = occurrence_after(d)
        iter += 1
      end

      return nil if cancelled_on?(d) # all skipped
      d
    else
      return nil if cancelled_on?(d)
      d
    end
  end

  # Час игры известен не всегда, а делить промежуток между занятиями надо и
  # тогда: у игры без времени занятие считаем с начала суток. Длительность по
  # умолчанию — час, как в анонсах срочного поиска.
  DEFAULT_DURATION_MINUTES = 60

  # Час занятия — в поясе создателя, ровно как его показывает start_at_for_ui.
  # Стрелки снимаем уже после перехода в этот пояс: колонка time зонозависимая,
  # и её значение — момент времени, а не циферблат. Считать часы у вызывающего
  # кода нельзя: одна и та же игра, открытая из московского и екатеринбургского
  # окружения, начиналась бы в разное время.
  def occurrence_starts_at(day)
    return nil if day.blank?

    day = day.to_date

    Time.use_zone(creator_time_zone) do
      at = time.present? ? time.in_time_zone : nil
      Time.zone.local(day.year, day.month, day.day, at&.hour.to_i, at&.min.to_i)
    end
  end

  def occurrence_ends_at(day)
    started_at = occurrence_starts_at(day)
    return nil if started_at.nil?

    started_at + (duration_minutes.to_i.positive? ? duration_minutes.to_i : DEFAULT_DURATION_MINUTES).minutes
  end

  # Ближайшее вхождение серии не раньше указанного дня. Шагаем по дням, а не по
  # неделям: у серии их теперь несколько на неделе, и следующая игра может быть
  # хоть завтра.
  def occurrence_on_or_after(day)
    return nil if date.blank?

    day = day.to_date
    day = date if day < date
    listed = scheduled_dates.find { |scheduled| scheduled >= day }
    return listed if listed
    return nil unless recurring? || recurring_monthly?

    # За последней отметкой шагаем по дням: ежемесячное число выпадает не в
    # каждом месяце (31-е февраля не бывает), но за год встречается наверняка.
    day = scheduled_dates.last + 1 if day <= scheduled_dates.last
    MAX_OCCURRENCE_SEARCH_DAYS.times do
      break if repeats_on?(day)

      day += 1
    end
    day if repeats_on?(day)
  end

  def occurrence_after(day)
    occurrence_on_or_after(day.to_date + 1)
  end

  # Ближайшее вхождение не позже указанного дня — до первой отметки серии не
  # существует.
  def occurrence_on_or_before(day)
    return nil if date.blank? || day.blank?

    day = day.to_date
    last_scheduled = scheduled_dates.last

    if day > last_scheduled && (recurring? || recurring_monthly?)
      MAX_OCCURRENCE_SEARCH_DAYS.times do
        break if day <= last_scheduled || repeats_on?(day)

        day -= 1
      end
      return day if day > last_scheduled && repeats_on?(day)
    end

    scheduled_dates.reverse.find { |scheduled| scheduled <= day }
  end

  def occurrence_before(day)
    return nil if day.blank?

    occurrence_on_or_before(day.to_date - 1)
  end

  def prebooking_horizon_dates(count = 3)
    return [] unless series?

    # Серия кончилась — записываться больше некуда: без этой проверки горизонт
    # начинался заново с первой даты расписания, то есть с уже отыгранной.
    start = next_date
    return [] if start.blank?

    count = count.to_i.clamp(3, MAX_PREBOOKING_HORIZON)
    dates = [ start.to_date ]
    # У конечной серии горизонт кончается вместе с расписанием.
    dates << occurrence_after(dates.last) while dates.size < count && occurrence_after(dates.last)
    dates
  end

  # Календарь предзаписи листается по месяцам: от месяца ближайшего занятия и
  # на год вперёд, а у конечной серии — до месяца её последней даты.
  MAX_PREBOOKING_MONTHS = 12

  def prebooking_month_range
    # По расписанию, а не по next_date: тот пропускает отменённые занятия, и
    # серия, у которой отменили всё оставшееся, лишалась бы календаря — а
    # вернуть дату можно только из него.
    first = occurrence_on_or_after(Date.current)&.beginning_of_month
    return nil if first.nil?

    last = ends_on ? [ ends_on.beginning_of_month, first ].max : first + (MAX_PREBOOKING_MONTHS - 1).months
    first..last
  end

  # Месяц для показа по запросу вроде «2026-10»: мусор и выход за границы
  # превращаются в ближайший допустимый, а не в ошибку.
  def prebooking_month(requested = nil)
    range = prebooking_month_range
    return nil unless range

    month = (Date.strptime(requested.to_s, "%Y-%m") rescue nil)
    month ? month.beginning_of_month.clamp(range.first, range.last) : range.first
  end

  # Даты предзаписи внутри месяца: занятия начиная с сегодняшнего дня — прошлые
  # уже не забронировать, — плюс те, где есть брони, отмены или тренер.
  # Отменённое занятие, которое ещё впереди, тоже показываем: его можно вернуть.
  def prebooking_dates_in(month)
    return [] unless series?

    from = [ month.beginning_of_month, Date.current ].max
    to = month.end_of_month
    return [] if from > to

    booked_dates = prebookings.where.not(user_id: nil).where(date: from..to).distinct.pluck(:date)
    cancelled_dates = prebooking_cancellations.where(date: from..to).distinct.pluck(:date)
    coach_dates = coach_prebookings.where(date: from..to).distinct.pluck(:date)

    (occurrences_between(from, to) + booked_dates + cancelled_dates + coach_dates).map(&:to_date).uniq.sort
  end

  # Все занятия в промежутке, включая отменённые.
  def occurrences_between(from, to)
    dates = []
    day = occurrence_on_or_after(from)

    while day && day <= to
      dates << day
      day = occurrence_after(day)
    end

    dates
  end

  # Число игроков организатор может оставить «пока не выбрано»: тогда карточки
  # не считают свободные места, а слотов пребукинга не бывает вовсе.
  def players_count_chosen?
    players_count.to_i > 0
  end

  # Сколько игроков нужно на игру (по умолчанию 4). Это же число — количество
  # слотов на дату в пребукинге.
  def required_players
    players_count_chosen? ? players_count.to_i : DEFAULT_PLAYERS
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

  # Занятие, чей состав сейчас в игре: у серии — ближайшее вхождение, у
  # разовой — её дата.
  def chat_window_occurrence
    recurring? ? (next_date || date) : date
  end

  def previous_occurrence_before_next_date
    return nil unless series? && next_date.present?

    prev = occurrence_before(next_date)
    max_iters = 520
    iter = 0

    # ОПТИМИЗАЦИЯ: используем cancelled_on?
    while prev && cancelled_on?(prev) && iter < max_iters
      prev = occurrence_before(prev)
      iter += 1
    end

    return nil if prev.nil? || cancelled_on?(prev)

    prev
  end

  # Пора ли сбрасывать состав: наступила ли ночь... вернее, вечер, в который
  # состав отыгранного занятия уступает место следующему. Всё про эту границу —
  # в Game::OccurrenceCycle.
  def participations_reset_due?(now = Time.current)
    occurrence_cycle.due?(now)
  end

  # Занятие, к которому относится состав после ближайшего сброса: на него
  # переносится предзапись и им отмечается сам сброс.
  def upcoming_occurrence(now = Time.current)
    occurrence_cycle.upcoming_occurrence(now)
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

  # Брони и отмены висят на конкретных занятиях, поэтому протухают, когда игра
  # переезжает на другую дату, перестаёт повторяться или теряет день из
  # расписания — а с календарём снять день стало обычным делом. Брать их с
  # собой нельзя: слот на несуществующем занятии остаётся в календаре
  # предзаписи, на него продолжают записываться, а в состав он уже не попадёт.
  def remove_stale_bookings
    coach_prebookings.where.not(coach_id: assigned_coach_ids).delete_all
    return unless saved_change_to_date? || saved_change_to_recurring? || saved_change_to_recurring_monthly? ||
                  saved_change_to_recurrence_days? || saved_change_to_occurrence_dates?

    unless series? && date.present?
      coach_prebookings.delete_all
      prebookings.delete_all
      prebooking_cancellations.delete_all
      return
    end

    drop_bookings_outside_schedule(coach_prebookings)
    drop_bookings_outside_schedule(prebookings)
    drop_bookings_outside_schedule(prebooking_cancellations)
  end

  def drop_bookings_outside_schedule(relation)
    stale_ids = relation.reject { |booking| occurrence_date?(booking.date) }.map(&:id)
    relation.where(id: stale_ids).delete_all if stale_ids.any?
  end

  # Срочный поиск включают и с сайта, и из телеграм-бота, поэтому оба канала —
  # рассылка по городу и внешний кросспостинг — висят на модели, а не на
  # контроллере: иначе один из входов молча остаётся без анонса.
  def announce_urgent_player_search
    return unless urgent_player_search?
    return unless saved_change_to_urgent_player_search?
    return unless self[:urgent_player_search]

    NotifyUrgentPlayerSearchJob.perform_later(id)
    Social.publish_urgent(self)
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
