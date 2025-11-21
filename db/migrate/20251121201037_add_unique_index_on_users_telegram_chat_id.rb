class AddUniqueIndexOnUsersTelegramChatId < ActiveRecord::Migration[8.0]
  def change
    # допускаем NULL, уникальность только для ненулевых значений
    add_index :users, :telegram_chat_id, unique: true, name: "index_users_on_telegram_chat_id_unique"
  end
end
