class AddStatusToParticipations < ActiveRecord::Migration[8.0]
  def change
    add_column :participations, :status, :string, default: "approved", null: false
    add_column :participations, :approved_at, :datetime

    reversible do |dir|
      dir.up do
        execute "UPDATE participations SET status = 'approved' WHERE status IS NULL"
      end
    end
  end
end
