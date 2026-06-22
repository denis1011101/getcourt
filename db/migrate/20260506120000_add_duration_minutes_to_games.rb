class AddDurationMinutesToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :duration_minutes, :integer
  end
end
