class AddTournamentToGames < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:games, :tournament_id)
      add_reference :games, :tournament, foreign_key: true, index: true
    end
  end
end
