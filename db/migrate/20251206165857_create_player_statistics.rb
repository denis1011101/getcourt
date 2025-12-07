class CreatePlayerStatistics < ActiveRecord::Migration[8.0]
  def change
    create_table :player_statistics do |t|
      t.references :user, null: false, foreign_key: true
      t.float :singles_hours
      t.float :doubles_hours
      t.integer :singles_sessions
      t.integer :doubles_sessions
      t.integer :singles_games
      t.integer :doubles_games
      t.integer :singles_wins
      t.integer :singles_losses
      t.integer :doubles_wins
      t.integer :doubles_losses
      t.integer :aces
      t.integer :double_faults
      t.float :first_serve_percent
      t.float :singles_rating
      t.float :doubles_rating

      t.timestamps
    end
  end
end
