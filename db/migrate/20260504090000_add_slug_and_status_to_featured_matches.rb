class AddSlugAndStatusToFeaturedMatches < ActiveRecord::Migration[8.1]
  class MigrationFeaturedMatch < ActiveRecord::Base
    self.table_name = "featured_matches"
  end

  def up
    add_column :featured_matches, :slug, :string
    add_column :featured_matches, :status, :string, null: false, default: "scheduled"
    add_column :featured_matches, :result, :text
    add_column :featured_matches, :description, :text
    add_column :featured_matches, :photo_credit, :string
    add_column :featured_matches, :photo_credit_url, :string

    MigrationFeaturedMatch.reset_column_information
    used_slugs = Set.new

    MigrationFeaturedMatch.find_each do |match|
      base_slug = [
        match.tournament_label,
        match.starts_at&.year,
        match.player_left_name,
        match.player_right_name
      ].compact.join(" ").parameterize.presence || "featured-match"

      slug = base_slug
      suffix = 2
      while used_slugs.include?(slug)
        slug = "#{base_slug}-#{suffix}"
        suffix += 1
      end

      used_slugs << slug
      match.update_columns(slug: slug)
    end

    change_column_null :featured_matches, :slug, false
    add_index :featured_matches, :slug, unique: true
  end

  def down
    remove_index :featured_matches, :slug
    remove_column :featured_matches, :photo_credit_url
    remove_column :featured_matches, :photo_credit
    remove_column :featured_matches, :description
    remove_column :featured_matches, :result
    remove_column :featured_matches, :status
    remove_column :featured_matches, :slug
  end
end
