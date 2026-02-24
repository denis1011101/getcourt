class RemoveUniqueIndexFromTournamentMatches < ActiveRecord::Migration[8.1]
  def change
    remove_index :tournament_matches, name: "index_tournament_matches_on_players"
    add_index :tournament_matches, [ :tournament_id, :player_a_id, :player_b_id ], name: "index_tournament_matches_on_players"
  end
end
