class CreateMatches < ActiveRecord::Migration[8.0]
  def change
    create_table :matches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :opponent, foreign_key: { to_table: :users }
      t.references :game, foreign_key: true

      t.string :mode, null: false
      t.string :outcome, null: false
      t.string :surface
      t.string :score
      t.datetime :played_at, null: false

      # расширяемо под ace/df/1st serve/etc
      t.json :stats, null: false, default: {}

      t.timestamps
    end

    add_index :matches, %i[user_id played_at]
    add_index :matches, %i[user_id mode played_at]
  end
end
