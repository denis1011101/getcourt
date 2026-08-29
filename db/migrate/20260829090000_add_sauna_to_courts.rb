class AddSaunaToCourts < ActiveRecord::Migration[8.1]
  def change
    add_column :courts, :sauna, :boolean, default: false, null: false
  end
end
