class AddUniqueIndexToParticipations < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      DELETE FROM participations
      WHERE id NOT IN (
        SELECT min_id FROM (
          SELECT MIN(id) AS min_id
          FROM participations
          GROUP BY user_id, game_id
        )
      )
    SQL

    add_index :participations, [ :user_id, :game_id ], unique: true, name: 'index_participations_on_user_and_game'
  end

  def down
    remove_index :participations, name: 'index_participations_on_user_and_game'
  end
end
