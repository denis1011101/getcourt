class Prebooking < ApplicationRecord
  belongs_to :game
  belongs_to :user, optional: true

  enum :status, { pending: "pending", approved: "approved" }

  validates :slot_index, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :date, presence: true
  validates :game_id, uniqueness: { scope: [ :date, :slot_index ] }

  validate :single_booking_per_user

  # Освобождает слот. Слот сверх мест заводили под конкретного человека —
  # пустым он не нужен. А в освободившийся обычный переезжает последний из
  # записанных сверх мест: иначе пустой слот звал бы записаться на дату, где
  # мест уже нет.
  def release!
    required = game.prebooking_required_players(date)
    return destroy! if slot_index > required

    extra = game.prebookings.where(date: date).where("slot_index > ?", required).where.not(user_id: nil).order(:slot_index).last
    transaction do
      if extra
        moved = extra.slice(:user_id, :status, :approved_at)
        extra.destroy!
        update!(moved)
      else
        update!(user: nil, status: "approved", approved_at: nil)
      end
    end
  end

  private

  def single_booking_per_user
    return if user_id.nil?

    dup = game.prebookings.where.not(id: id).where(user_id: user_id, date: date)
    if dup.exists?
      errors.add(:user_id, "can have only one booking for this game on the same date")
    end
  end
end
