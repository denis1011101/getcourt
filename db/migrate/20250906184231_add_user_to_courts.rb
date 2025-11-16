class AddUserToCourts < ActiveRecord::Migration[8.0]
  def change
    add_reference :courts, :user, foreign_key: true, index: true
  end
end
