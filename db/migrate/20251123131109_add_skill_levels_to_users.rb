class AddSkillLevelsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :skill_levels, :json, default: {}, null: false

    reversible do |dir|
      dir.up do
        User.reset_column_information
        User.find_each do |u|
          next if u.skill_level.blank?
          levels = {}
          User::SPORTS.each { |s| levels[s] = u.skill_level }
          u.update_column(:skill_levels, levels)
        end
      end
    end

    # optionally keep old :skill_level for backwards compat; remove later in a separate migration
  end
end
