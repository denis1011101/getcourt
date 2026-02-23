class TournamentMatch < ApplicationRecord
  belongs_to :tournament
  belongs_to :player_a, class_name: "User"
  belongs_to :player_b, class_name: "User"
  belongs_to :player_a2, class_name: "User", optional: true
  belongs_to :player_b2, class_name: "User", optional: true

  enum :result, { player_a: "player_a", player_b: "player_b", draw: "draw" }

  validates :score, :result, :played_at, presence: true
end
