class MakeNotificationChannelGlobal < ActiveRecord::Migration[8.1]
  def up
    rename_column :users, :nearby_notification_channel, :notification_channel

    # The column already carries choices users made on /users/notifications, and
    # it now drives every notification rather than just the nearby ones, so only
    # backfill rows that never got a value.
    execute <<~SQL.squish
      UPDATE users
      SET notification_channel = CASE
        WHEN telegram_chat_id IS NOT NULL THEN 'telegram'
        ELSE 'email'
      END
      WHERE notification_channel IS NULL OR notification_channel = ''
    SQL
  end

  def down
    rename_column :users, :notification_channel, :nearby_notification_channel
  end
end
