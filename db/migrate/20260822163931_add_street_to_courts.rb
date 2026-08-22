class AddStreetToCourts < ActiveRecord::Migration[8.1]
  def change
    add_column :courts, :street, :string
  end
end
