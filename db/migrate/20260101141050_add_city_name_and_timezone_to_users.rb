class AddCityNameAndTimezoneToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :city_name, :string unless column_exists?(:users, :city_name)
    add_column :users, :timezone, :string unless column_exists?(:users, :timezone)
  end
end
