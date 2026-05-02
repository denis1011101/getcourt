class MakePlayerFlagsOptionalInFeaturedMatches < ActiveRecord::Migration[8.1]
  def change
    change_column_null :featured_matches, :player_left_flag, true
    change_column_null :featured_matches, :player_right_flag, true
  end
end
