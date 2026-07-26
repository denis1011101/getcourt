class AddRecentInviteHandlesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :recent_invite_handles, :json, default: [], null: false
  end
end
