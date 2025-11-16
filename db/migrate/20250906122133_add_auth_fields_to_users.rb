class AddAuthFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :email, :string unless column_exists?(:users, :email)
    add_column :users, :name, :string unless column_exists?(:users, :name)
    add_column :users, :admin, :boolean, default: false, null: false unless column_exists?(:users, :admin)
    add_index  :users, :email, unique: true, where: "email IS NOT NULL"
  end
end
