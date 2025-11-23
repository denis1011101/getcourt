class AddVerificationPrefsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :require_verification, :boolean, default: false, null: false
    add_column :users, :preferred_login_via, :string
  end
end
