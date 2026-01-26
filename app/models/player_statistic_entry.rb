class PlayerStatisticEntry < ApplicationRecord
  belongs_to :user
  belongs_to :game
  belongs_to :actor, class_name: "User"

  validates :source, presence: true
  validates :data, presence: true
  validates :recorded_at, presence: true
end
