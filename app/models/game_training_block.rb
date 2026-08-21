class GameTrainingBlock < ApplicationRecord
  belongs_to :game
  belongs_to :training_block

  validates :training_block_id, uniqueness: { scope: :game_id }

  scope :ordered, -> { order(:position, :id) }
end
