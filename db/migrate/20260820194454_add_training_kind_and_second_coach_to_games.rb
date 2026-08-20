class AddTrainingKindAndSecondCoachToGames < ActiveRecord::Migration[8.1]
  def up
    add_column :games, :kind, :string, null: false, default: "game"
    add_index :games, :kind
    add_reference :games, :second_coach, foreign_key: { to_table: :users }
    add_column :games, :second_coach_invitation_status, :string

    # Тренер бывает только у тренировки, поэтому старые игры с тренером ею и становятся.
    execute "UPDATE games SET kind = 'training' WHERE with_coach = 1"
  end

  def down
    remove_column :games, :second_coach_invitation_status
    remove_reference :games, :second_coach
    remove_index :games, :kind
    remove_column :games, :kind
  end
end
