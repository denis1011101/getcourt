class PrebookingCancellation < ApplicationRecord
  belongs_to :game
  belongs_to :user

  validates :date, presence: true
  validates :game_id, uniqueness: { scope: :date }
end
