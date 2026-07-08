class AddGuestNameToParticipations < ActiveRecord::Migration[8.0]
  def change
    add_column :participations, :guest_name, :string
    change_column_null :participations, :user_id, true
  end
end
