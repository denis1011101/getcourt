class AddRecurrenceDaysToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :recurrence_days, :text
  end
end
