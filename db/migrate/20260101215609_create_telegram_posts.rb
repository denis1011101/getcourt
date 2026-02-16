class CreateTelegramPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :telegram_posts do |t|
      t.references :telegram_channel, null: false, foreign_key: true
      t.bigint :message_id, null: false
      t.text :text
      # use jsonb on Postgres, fallback to json on SQLite
      if ActiveRecord::Base.connection.adapter_name.downcase.start_with?("post")
        t.jsonb :extra, default: {}
      else
        t.json :extra, default: {}
      end
      t.datetime :published_at

      t.timestamps
    end

    add_index :telegram_posts, [ :telegram_channel_id, :message_id ], unique: true
    add_index :telegram_posts, :published_at
  end
end
