class TournamentCourt < ApplicationRecord
  belongs_to :tournament
  belongs_to :court
end
