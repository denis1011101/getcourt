class CreateGameScoreboards < ActiveRecord::Migration[8.1]
  def change
    create_table :game_scoreboards do |t|
      t.references :game, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "live"
      t.json :settings, null: false, default: {}
      t.json :team_a, null: false, default: {}
      t.json :team_b, null: false, default: {}
      t.json :actions, null: false, default: []
      t.datetime :finished_at
      t.timestamps
    end

    # Табло у игры одно живое: второй телефон подхватывает текущий матч, а не
    # заводит параллельный счёт.
    add_index :game_scoreboards, :game_id, unique: true, where: "status = 'live'", name: "index_game_scoreboards_one_live_per_game"
  end
end
