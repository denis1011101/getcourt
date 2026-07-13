class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :nearby_notification_channel, :string
    add_column :users, :locale, :string

    execute <<~SQL.squish
      UPDATE users
      SET nearby_notification_channel = CASE
        WHEN notify_nearby = TRUE THEN 'telegram'
        WHEN telegram_chat_id IS NOT NULL THEN 'telegram'
        ELSE 'email'
      END
    SQL
  end

  def down
    remove_column :users, :locale
    remove_column :users, :nearby_notification_channel
  end
end
