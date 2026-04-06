class AddFavoriteCourtsAndCourtPreferencesNoteToUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :favorite_courts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :court, null: false, foreign_key: true

      t.timestamps
    end

    add_index :favorite_courts, [ :user_id, :court_id ], unique: true
    add_column :users, :court_preferences_note, :text
  end
end
