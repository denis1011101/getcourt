class AddSurfaceLabelToFeaturedMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :featured_matches, :surface_label, :string
  end
end
