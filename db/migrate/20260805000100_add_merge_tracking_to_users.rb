class AddMergeTrackingToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :merged_into, foreign_key: { to_table: :users }
    add_column :users, :merged_at, :datetime
  end
end
