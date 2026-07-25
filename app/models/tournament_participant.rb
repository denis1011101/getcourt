class TournamentParticipant < ApplicationRecord
  belongs_to :tournament
  belongs_to :user
  enum :status, { pending: "pending", approved: "approved" }
  validates :status, presence: true
  validates :user_id, uniqueness: { scope: :tournament_id }

  def display_name
    name.presence || user&.name.presence || user&.email
  end

  def approve!
    update!(status: "approved", approved_at: Time.current)
  end
end
