class AddSharedToTrainingBlocks < ActiveRecord::Migration[8.1]
  def change
    # Общий блок GetCourt доступен любому организатору, поэтому владелец у него
    # остаётся прежним, а видимость задаёт отдельный флаг.
    add_column :training_blocks, :shared, :boolean, null: false, default: false
    add_index :training_blocks, :shared
  end
end
