class CreateSocialPosts < ActiveRecord::Migration[8.1]
  def up
    create_table :social_posts do |t|
      t.string :network,   null: false
      t.string :kind,      null: false   # welcome | urgent | daily
      t.string :dedup_key, null: false   # "getcourt" | "game:42" | "fact:total_hours:2026-08-30"
      t.string :external_post_id
      t.datetime :posted_at
      t.timestamps
    end
    add_index :social_posts, %i[network kind dedup_key], unique: true
    # Выбор варианта для daily-поста ходит именно этим путём: чем дольше вариант
    # не постился, тем он приоритетнее.
    add_index :social_posts, %i[network kind posted_at]

    # Threads постил в те же аккаунты до появления таблицы — переносим, чтобы
    # старые игры не ушли в сеть повторно. Колонки на games дропаем отдельной
    # миграцией, когда новая схема поживёт на проде.
    execute(<<~SQL.squish)
      INSERT INTO social_posts (network, kind, dedup_key, external_post_id, posted_at, created_at, updated_at)
      SELECT 'threads', 'urgent', 'game:' || id, threads_post_id,
             COALESCE(threads_posted_at, CURRENT_TIMESTAMP),
             CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM games
      WHERE threads_post_id IS NOT NULL AND threads_post_id != ''
    SQL
  end

  def down
    drop_table :social_posts
  end
end
