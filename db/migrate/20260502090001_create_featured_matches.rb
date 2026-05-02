class CreateFeaturedMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :featured_matches do |t|
      t.string :tournament_label, null: false
      t.string :player_left_name, null: false
      t.string :player_left_flag, null: false
      t.string :player_right_name, null: false
      t.string :player_right_flag, null: false
      t.datetime :starts_at, null: false
      t.boolean :active, null: false, default: false

      t.timestamps
    end

    add_index :featured_matches, :active, unique: true, where: "active = 1"
    add_index :featured_matches, :starts_at
  end
end
