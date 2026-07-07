class AddStatsResetAtToPlayerStatistics < ActiveRecord::Migration[8.1]
  def change
    add_column :player_statistics, :stats_reset_at, :datetime
  end
end
