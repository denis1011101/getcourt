class CreateTournamentDates < ActiveRecord::Migration[8.0]
  def change
    create_table :tournament_dates do |t|
      t.references :tournament, null: false, foreign_key: true
      t.date :date

      t.timestamps
    end
  end
end
