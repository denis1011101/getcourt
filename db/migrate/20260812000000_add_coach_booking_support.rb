class AddCoachBookingSupport < ActiveRecord::Migration[8.0]
  def change
    add_reference :games, :coach, foreign_key: { to_table: :users }
    add_column :games, :coach_invitation_status, :string

    create_table :coach_prebookings do |t|
      t.references :game, null: false, foreign_key: true
      t.references :coach, null: false, foreign_key: { to_table: :users }
      t.date :date, null: false
      t.timestamps
    end

    add_index :coach_prebookings, [ :game_id, :coach_id, :date ], unique: true
  end
end
