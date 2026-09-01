class AddShowInFeedToGameMedia < ActiveRecord::Migration[8.1]
  def up
    add_column :game_media, :show_in_feed, :boolean, default: false, null: false
    add_index :game_media, :show_in_feed

    # Загруженное до этой миграции лента показывает прямо сейчас. Выключить
    # галку всем задним числом — значит молча снять с витрины чужие фото,
    # поэтому по умолчанию она выключена только для будущих загрузок.
    connection.update("UPDATE game_media SET show_in_feed = #{connection.quoted_true}")
  end

  def down
    remove_index :game_media, :show_in_feed
    remove_column :game_media, :show_in_feed
  end
end
