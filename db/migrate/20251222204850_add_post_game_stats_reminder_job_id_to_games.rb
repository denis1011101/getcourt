class AddPostGameStatsReminderJobIdToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :post_game_stats_reminder_job_id, :string
  end
end
