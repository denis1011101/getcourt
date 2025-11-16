class AddRecurringToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :recurring, :boolean, default: false, null: false
    add_column :games, :occurrences_per_week, :integer, default: 1, null: false
    add_column :games, :time2, :time
    add_index :games, :recurring
  end
end
