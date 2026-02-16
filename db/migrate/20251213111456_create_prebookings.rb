class CreatePrebookings < ActiveRecord::Migration[8.0]
  def change
    create_table :prebookings do |t|
      t.references :game, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :slot_index, null: false
      t.references :user, foreign_key: true, null: true

      t.timestamps
    end

    add_index :prebookings, [ :game_id, :date, :slot_index ], unique: true, name: "index_prebookings_on_game_date_slot"
  end
end
