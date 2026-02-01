class AddModerationStatusToCourts < ActiveRecord::Migration[8.0]
  def change
    add_column :courts, :moderation_status, :string, null: false, default: "pending"
    add_column :courts, :approved_at, :datetime
    add_index :courts, :moderation_status
  end
end
