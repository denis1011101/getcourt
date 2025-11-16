class Participation < ApplicationRecord
  belongs_to :game
  belongs_to :user

  validates :user_id, uniqueness: { scope: :game_id, message: "has already joined this game" }
end
