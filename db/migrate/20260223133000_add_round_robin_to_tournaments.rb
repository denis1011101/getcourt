class AddRoundRobinToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :tournament_type, :string, null: false, default: "bracket"
    add_index :tournaments, :tournament_type

    create_table :tournament_matches do |t|
      t.references :tournament, null: false, foreign_key: true
      t.references :player_a, null: false, foreign_key: { to_table: :users }
      t.references :player_b, null: false, foreign_key: { to_table: :users }
      t.references :player_a2, null: true, foreign_key: { to_table: :users }
      t.references :player_b2, null: true, foreign_key: { to_table: :users }
      t.string :score
      t.string :result
      t.datetime :played_at
      t.timestamps
      t.index [ :tournament_id, :player_a_id, :player_b_id ], unique: true, name: "index_tournament_matches_on_players"
    end
  end
end
