class AddReleaseCourtOnResetToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :release_court_on_reset, :boolean, default: false, null: false
  end
end
