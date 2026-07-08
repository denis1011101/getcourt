class Participation < ApplicationRecord
  belongs_to :game
  belongs_to :user, optional: true

  enum :status, { pending: "pending", approved: "approved" }

  validates :user_id, uniqueness: { scope: :game_id, message: "has already joined this game" }, allow_nil: true
  validates :user, presence: true, if: -> { user_id.present? }
  validates :status, presence: true
  validates :guest_name, presence: true, length: { maximum: 50 }, if: -> { user_id.blank? }
  validates :guest_name, absence: true, if: -> { user_id.present? }
  validates :guest_name, uniqueness: { scope: :game_id, case_sensitive: false }, allow_blank: true

  scope :guests, -> { where(user_id: nil) }

  def guest?
    user_id.nil?
  end

  def display_name
    guest? ? guest_name : (user.name.presence || user.email)
  end
end
