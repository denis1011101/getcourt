class RestoreFeaturedMatchesActiveUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :featured_matches, name: "index_featured_matches_on_active", if_exists: true
    add_index :featured_matches, :active, unique: true, where: "active = 1", name: "index_featured_matches_on_active"
  end
end
