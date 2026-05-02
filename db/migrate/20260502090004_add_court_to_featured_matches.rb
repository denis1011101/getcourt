class AddCourtToFeaturedMatches < ActiveRecord::Migration[8.1]
  def change
    add_reference :featured_matches, :court, foreign_key: true, null: true
  end
end
