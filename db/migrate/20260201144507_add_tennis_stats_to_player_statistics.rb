class AddTennisStatsToPlayerStatistics < ActiveRecord::Migration[8.0]
  def change
    add_column :player_statistics, :individual_training, :integer
    add_column :player_statistics, :group_training, :integer
    add_column :player_statistics, :break_points_saved, :integer
    add_column :player_statistics, :break_points_converted, :integer
    add_column :player_statistics, :winners, :integer
    add_column :player_statistics, :unforced_errors, :integer
    add_column :player_statistics, :net_points_won, :integer
    add_column :player_statistics, :service_points_won, :integer
    add_column :player_statistics, :return_points_won, :integer
    add_column :player_statistics, :return_games_won, :integer
    add_column :player_statistics, :games_won_total, :integer
  end
end
