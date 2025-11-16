class AddTelegramToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :telegram_username, :string
    add_column :users, :telegram_chat_id, :bigint
    add_index  :users, :telegram_username
  end
end
