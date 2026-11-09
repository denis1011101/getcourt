class ChangeNotifyNearbyDefaultOnUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :notify_nearby, from: false, to: true
  end
end
