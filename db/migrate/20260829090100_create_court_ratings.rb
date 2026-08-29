class CreateCourtRatings < ActiveRecord::Migration[8.1]
  def change
    create_table :court_ratings do |t|
      t.references :court, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :value, null: false

      t.timestamps
    end

    add_index :court_ratings, [ :court_id, :user_id ], unique: true

    # Средняя оценка нужна в списке кортов, где корты уже отобраны в память
    # и посчитать её запросом на всех сразу негде — держим её на самом корте.
    add_column :courts, :ratings_count, :integer, default: 0, null: false
    add_column :courts, :ratings_average, :decimal, precision: 3, scale: 2, default: 0, null: false
  end
end
