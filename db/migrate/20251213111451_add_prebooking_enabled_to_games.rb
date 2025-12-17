class AddPrebookingEnabledToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :prebooking_enabled, :boolean, default: false, null: false
    add_index :games, :prebooking_enabled
  end
end
