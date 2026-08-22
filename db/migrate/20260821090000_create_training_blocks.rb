class CreateTrainingBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :training_blocks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :duration_minutes

      t.timestamps
    end

    # Библиотека тренера — набор уникальных блоков, чтобы один и тот же
    # блок не заводился заново при каждом добавлении из формы игры.
    add_index :training_blocks, [ :user_id, :title ], unique: true

    create_table :game_training_blocks do |t|
      t.references :game, null: false, foreign_key: true
      t.references :training_block, null: false, foreign_key: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :game_training_blocks, [ :game_id, :training_block_id ], unique: true
  end
end
