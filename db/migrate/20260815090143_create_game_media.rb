class CreateGameMedia < ActiveRecord::Migration[8.1]
  def change
    create_table :game_media do |t|
      t.references :game, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      # Модерация: лента публичная и индексируется, поэтому у админа должен быть
      # способ убрать вложение, не удаляя его у автора.
      t.datetime :hidden_at

      t.timestamps
    end

    add_index :game_media, :hidden_at
  end
end
