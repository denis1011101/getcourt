class AddUrgentPlayerSearchToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :urgent_player_search, :boolean, default: false, null: false
    add_index :games, :urgent_player_search
  end
end
