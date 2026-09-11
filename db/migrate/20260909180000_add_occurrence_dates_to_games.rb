class AddOccurrenceDatesToGames < ActiveRecord::Migration[8.1]
  def up
    add_column :games, :occurrence_dates, :text
    add_column :games, :recurring_monthly, :boolean, null: false, default: false
    # Последнее занятие серии: у бесконечной его нет, и колонка остаётся пустой.
    # По ней списки и уборка отличают отыгранную серию от той, что ещё впереди.
    add_column :games, :ends_on, :date
    add_index :games, :ends_on

    execute "UPDATE games SET ends_on = date WHERE recurring = 0"
  end

  def down
    remove_column :games, :occurrence_dates
    remove_column :games, :recurring_monthly
    remove_column :games, :ends_on
  end
end
