class Prebooking < ApplicationRecord
  belongs_to :game
  belongs_to :user, optional: true

  enum :status, { pending: "pending", approved: "approved" }

  validates :slot_index, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :date, presence: true
  validates :game_id, uniqueness: { scope: [:date, :slot_index] }

  validate :single_booking_per_user

  private

  def single_booking_per_user
    return if user_id.nil?

    dup = game.prebookings.where.not(id: id).where(user_id: user_id, date: date)
    if dup.exists?
      errors.add(:user_id, "can have only one booking for this game on the same date")
    end
  end
end
