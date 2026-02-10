class AddCityNameToCourts < ActiveRecord::Migration[8.0]
  def change
    add_column :courts, :city_name, :string
    add_index :courts, :city_name
  end
end
