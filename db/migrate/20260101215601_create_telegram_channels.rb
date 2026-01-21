class CreateTelegramChannels < ActiveRecord::Migration[8.0]
  def change
    create_table :telegram_channels do |t|
      t.string :username, null: false
      t.string :url
      t.string :title
      t.bigint :last_message_id

      t.timestamps
    end

    add_index :telegram_channels, :username, unique: true
  end
end
