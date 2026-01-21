class AddBracketToTournaments < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments, :bracket_data, :jsonb, default: {}
    add_column :tournaments, :selected_variant, :integer
  end
end
