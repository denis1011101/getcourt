class AddDiagramToTrainingBlocks < ActiveRecord::Migration[8.1]
  def change
    # Схема лежит одним JSON-полем, а не отдельными таблицами фигур: она всегда
    # читается и пишется целиком вместе с блоком, а искать по координатам игроков
    # мы никогда не будем.
    add_column :training_blocks, :diagram, :json, null: false, default: {}
  end
end
