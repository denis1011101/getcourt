class AddWithCoachToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :with_coach, :boolean, default: false, null: false
    add_index :games, :with_coach
  end
end
