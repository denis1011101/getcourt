class AddTimeToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :time, :time
  end
end
