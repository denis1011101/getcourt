class CreateGames < ActiveRecord::Migration[8.0]
  def change
    create_table :games do |t|
      t.date :date
      t.time :time
      t.references :court, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
