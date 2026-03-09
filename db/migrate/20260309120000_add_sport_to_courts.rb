class AddSportToCourts < ActiveRecord::Migration[8.1]
  def change
    add_column :courts, :sport, :string
    add_index :courts, :sport
  end
end
