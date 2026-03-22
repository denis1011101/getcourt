class MakePlayerStatisticEntryGameIdNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :player_statistic_entries, :game_id, true
  end
end
