class AddStatusToTournamentParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_participants, :status, :string, null: false, default: "approved"
    add_column :tournament_participants, :approved_at, :datetime
    add_index :tournament_participants, :status
    add_index :tournament_participants, [ :tournament_id, :user_id ], unique: true, name: "index_tournament_participants_on_tournament_and_user"
  end
end
