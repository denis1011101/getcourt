class AddSportAndSkillLevelToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :sport, :string
    add_column :games, :skill_level, :string
  end
end
