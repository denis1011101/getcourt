class TournamentParticipant < ApplicationRecord
  belongs_to :tournament
  belongs_to :user
  validates :user_id, uniqueness: { scope: :tournament_id }
end
