class AddSkillCoachAndPreferredSportsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :skill_level, :string
    add_column :users, :coach, :boolean, default: false, null: false
    add_column :users, :preferred_sports, :text
    add_index :users, :skill_level
  end
end
