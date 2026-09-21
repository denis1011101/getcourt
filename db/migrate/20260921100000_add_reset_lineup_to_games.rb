class AddResetLineupToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :reset_lineup, :boolean, default: true, null: false
  end
end
