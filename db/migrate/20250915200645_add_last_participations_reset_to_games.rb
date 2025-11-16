class AddLastParticipationsResetToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :last_participations_reset_at, :date
  end
end
