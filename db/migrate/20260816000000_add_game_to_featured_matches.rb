class AddGameToFeaturedMatches < ActiveRecord::Migration[8.1]
  def change
    add_reference :featured_matches, :game, foreign_key: true
  end
end
