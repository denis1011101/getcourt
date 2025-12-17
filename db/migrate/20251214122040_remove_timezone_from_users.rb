class RemoveTimezoneFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_index :users, :timezone if index_exists?(:users, :timezone)
    remove_column :users, :timezone, :string
  end
end
