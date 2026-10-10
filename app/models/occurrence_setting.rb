# Настройки одного занятия серии: тип (игра или тренировка, с тренером или
# без), тренеры, корт и число игроков на эту дату. Тренеры здесь — только
# назначение на дату: приглашений, как у серии, им не уходит. Пусто — значит «как в серии».
# Совпадающее с серией не храним: поменяют серию — дата пойдёт за ней.
class OccurrenceSetting < ApplicationRecord
  PLAYERS_RANGE = (1..4)

  belongs_to :game
  belongs_to :court, optional: true
  belongs_to :coach, class_name: "User", optional: true
  belongs_to :second_coach, class_name: "User", optional: true

  before_validation :normalize

  validates :date, presence: true, uniqueness: { scope: :game_id }
  validates :kind, inclusion: { in: Game::KINDS }, allow_nil: true
  validates :players_count, inclusion: { in: PLAYERS_RANGE }, allow_nil: true
  validates :guest_coach_name, length: { maximum: 50 }
  validate :coaches_differ
  validate :players_fit_bookings

  after_save :sync_prebooking_slots, if: :saved_change_to_players_count?
  after_destroy :sync_prebooking_slots

  def blank_setting?
    kind.nil? && with_coach.nil? && !coaches_set? && court_id.nil? && !without_court? && players_count.nil?
  end

  def effective_kind
    kind || game.kind
  end

  def effective_with_coach?
    with_coach.nil? ? game.with_coach? : with_coach
  end

  def coaches_set?
    coach_id.present? || second_coach_id.present? || guest_coach_name.present?
  end

  def coach_names
    [ coach, second_coach ].compact.map { |user| user.name.presence || user.email } + [ guest_coach_name ].compact
  end

  private

  # Тренер бывает только на тренировке — как и в форме игры.
  def normalize
    self.kind = kind.presence
    self.with_coach = false if effective_kind == "game"
    self.kind = nil if kind == game.kind
    self.with_coach = nil if !with_coach.nil? && with_coach == game.with_coach?
    normalize_coaches
    self.court_id = court_id.presence
    self.without_court = false if court_id
    self.players_count = players_count.presence&.to_i
  end

  # Тренеры, как у серии, — пустые: дата пойдёт за серией. Без тренера на
  # дату тренеров нет вовсе.
  def normalize_coaches
    self.guest_coach_name = guest_coach_name.to_s.squish.presence
    if effective_kind == "game" || !effective_with_coach?
      self.coach_id = self.second_coach_id = self.guest_coach_name = nil
      return
    end

    self.coach_id = nil if coach_id == game.coach_id
    self.second_coach_id = nil if second_coach_id == game.second_coach_id
    self.guest_coach_name = nil if guest_coach_name == game.guest_coach_name
  end

  def coaches_differ
    errors.add(:second_coach_id, :same_as_coach) if coach_id.present? && coach_id == second_coach_id
  end

  # Уже записавшихся с даты молча не выкидываем: сначала их надо снять.
  def players_fit_bookings
    return if players_count.nil?

    booked = game.prebookings.where(date: date).where.not(user_id: nil).count
    errors.add(:players_count, :less_than_booked, count: booked) if booked > players_count
  end

  # Лишние пустые слоты убираем, занятые сдвигаем вверх — номера слотов идут
  # подряд, и брони не теряются.
  def sync_prebooking_slots
    return unless game.prebooking_enabled?

    required = destroyed? ? game.required_players : game.prebooking_required_players(date)
    slots = game.prebookings.where(date: date).order(Arel.sql("user_id IS NULL"), :slot_index).to_a
    slots.drop(required).select { |slot| slot.user_id.nil? }.each(&:destroy!)
    kept = slots.first(required)
    kept.each_with_index { |slot, i| slot.update_columns(slot_index: -(i + 1)) }
    kept.each_with_index { |slot, i| slot.update_columns(slot_index: i + 1) }
    game.ensure_prebookings_for_dates([ date ])
  end
end
