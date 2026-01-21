class AddNameToTournaments < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments, :name, :string
  end
end
