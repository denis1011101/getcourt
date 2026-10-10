class CreateOccurrenceSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :occurrence_settings do |t|
      t.references :game, null: false, foreign_key: true
      t.date :date, null: false
      # Тип и тренер на эту дату; пусто — как в серии.
      t.string :kind
      t.boolean :with_coach
      t.references :coach, foreign_key: { to_table: :users }
      t.references :second_coach, foreign_key: { to_table: :users }
      t.string :guest_coach_name
      t.references :court, foreign_key: true
      # Корт серии на эту дату не нужен: пустой court_id значит «как в серии».
      t.boolean :without_court, null: false, default: false
      t.integer :players_count
      t.timestamps
    end
    add_index :occurrence_settings, [ :game_id, :date ], unique: true
  end
end
