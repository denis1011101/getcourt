class AddStatusToPrebookings < ActiveRecord::Migration[8.0]
  def change
    add_column :prebookings, :status, :string, default: "approved", null: false
    add_column :prebookings, :approved_at, :datetime
  end
end
