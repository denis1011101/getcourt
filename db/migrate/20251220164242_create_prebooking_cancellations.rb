class CreatePrebookingCancellations < ActiveRecord::Migration[8.0]
  def change
    create_table :prebooking_cancellations do |t|
      t.references :game, null: false, foreign_key: true
      t.date :date, null: false
      t.references :user, null: false, foreign_key: { to_table: :users } # cancelled_by
      t.datetime :cancelled_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.timestamps
    end

    add_index :prebooking_cancellations, [:game_id, :date], unique: true
  end
end
