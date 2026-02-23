class AddGamesCountToTournaments < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments, :games_count, :integer
  end
end
