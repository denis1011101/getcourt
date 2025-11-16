class AddContactToCourts < ActiveRecord::Migration[8.0]
  def change
    add_column :courts, :contact_type, :string
    add_column :courts, :contact_value, :string
  end
end
