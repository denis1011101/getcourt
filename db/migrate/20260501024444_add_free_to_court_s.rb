class AddFreeToCourtS < ActiveRecord::Migration[8.1]
  def change
    add_column :courts, :free, :boolean, default: false, null: false
  end
end
