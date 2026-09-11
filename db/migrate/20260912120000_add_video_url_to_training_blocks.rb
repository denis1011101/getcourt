class AddVideoUrlToTrainingBlocks < ActiveRecord::Migration[8.1]
  def change
    add_column :training_blocks, :video_url, :string
  end
end
