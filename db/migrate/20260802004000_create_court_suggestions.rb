class CreateCourtSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :court_suggestions do |t|
      t.references :court, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.json :payload, null: false, default: {}
      t.text :comment
      t.string :status, null: false, default: "pending"
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :court_suggestions, %i[court_id status]
  end
end
