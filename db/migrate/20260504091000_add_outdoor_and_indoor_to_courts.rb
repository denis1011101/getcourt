class AddOutdoorAndIndoorToCourts < ActiveRecord::Migration[8.1]
  def change
    add_column :courts, :outdoor, :boolean, default: false, null: false
    add_column :courts, :indoor, :boolean, default: false, null: false
  end
end
