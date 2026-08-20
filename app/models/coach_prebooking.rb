class CoachPrebooking < ApplicationRecord
  belongs_to :game
  belongs_to :coach, class_name: "User"

  validates :date, presence: true
  validates :date, uniqueness: { scope: [ :game_id, :coach_id ] }
  validate :coach_matches_game
  validate :date_is_bookable_occurrence

  private

  def coach_matches_game
    errors.add(:coach, "must be the accepted game coach") unless game&.accepted_coach?(coach_id)
  end

  def date_is_bookable_occurrence
    return if date.blank? || game.blank?

    valid = game.recurring? && game.occurrence_date?(date) &&
      date >= Date.current && !game.cancelled_on?(date)
    errors.add(:date, "must be an upcoming game occurrence") unless valid
  end
end
