class TournamentParticipant < ApplicationRecord
  belongs_to :tournament
  belongs_to :user
  enum :status, { pending: "pending", approved: "approved" }
  validates :status, presence: true
  validates :user_id, uniqueness: { scope: :tournament_id }
end
