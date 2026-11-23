class CreateCourtPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :court_photos do |t|
      t.references :court, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :court_photos, %i[court_id status]
  end
end
