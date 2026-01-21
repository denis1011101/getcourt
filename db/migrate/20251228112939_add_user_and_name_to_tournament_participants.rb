class AddUserAndNameToTournamentParticipants < ActiveRecord::Migration[8.0]
  def change
    add_reference :tournament_participants, :user, foreign_key: true unless column_exists?(:tournament_participants, :user_id)
    add_column    :tournament_participants, :name, :string               unless column_exists?(:tournament_participants, :name)
  end
end
