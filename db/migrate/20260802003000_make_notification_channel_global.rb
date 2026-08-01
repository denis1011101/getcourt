class MakeNotificationChannelGlobal < ActiveRecord::Migration[8.1]
  def up
    rename_column :users, :nearby_notification_channel, :notification_channel

    execute <<~SQL.squish
      UPDATE users
      SET notification_channel = CASE
        WHEN telegram_chat_id IS NOT NULL THEN 'telegram'
        ELSE 'email'
      END
    SQL
  end

  def down
    rename_column :users, :notification_channel, :nearby_notification_channel
  end
end
