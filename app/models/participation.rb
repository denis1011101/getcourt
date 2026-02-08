class Participation < ApplicationRecord
  belongs_to :game
  belongs_to :user

  enum :status, { pending: "pending", approved: "approved" }

  validates :user_id, uniqueness: { scope: :game_id, message: "has already joined this game" }
  validates :status, presence: true
end
