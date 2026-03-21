class AddTextEnToTelegramPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :telegram_posts, :text_en, :text
  end
end
