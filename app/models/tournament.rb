class Tournament < ApplicationRecord
  belongs_to :user, optional: true
  has_many :games
  has_many :tournament_courts
  has_many :courts, through: :tournament_courts

  # participants who joined the tournament
  has_many :tournament_participants, dependent: :destroy

  # bracket_data stores generated bracket structure (JSON), selected_variant stores index
  # add corresponding migrations (see db/migrate below)
end
