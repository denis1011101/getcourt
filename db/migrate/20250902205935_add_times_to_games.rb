class AddTimesToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :times, :text, default: "[]", null: false
  end
end
