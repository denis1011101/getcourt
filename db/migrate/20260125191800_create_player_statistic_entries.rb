class CreatePlayerStatisticEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :player_statistic_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :game, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :source, null: false, default: "telegram"
      t.json :data, null: false, default: {}
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :player_statistic_entries, %i[user_id game_id source],
              unique: true,
              name: "index_ps_entries_on_user_game_source"
  end
end
