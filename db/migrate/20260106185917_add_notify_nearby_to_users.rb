class AddNotifyNearbyToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :notify_nearby, :boolean, default: false, null: false
  end
end
