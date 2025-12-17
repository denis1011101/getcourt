class AddTimezoneToCourts < ActiveRecord::Migration[8.0]
  def change
    add_column :courts, :timezone, :string
    add_index :courts, :timezone
  end
end
