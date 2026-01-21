class CreateTournamentCourts < ActiveRecord::Migration[8.0]
  def change
    create_table :tournament_courts do |t|
      t.references :tournament, null: false, foreign_key: true
      t.references :court, null: false, foreign_key: true

      t.timestamps
    end
  end
end
