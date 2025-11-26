class AddPlayersCountToGames < ActiveRecord::Migration[7.0]
  def change
    add_column :games, :players_count, :integer, default: 4, null: false
  end
end
