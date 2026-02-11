class AddTelegramLocaleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :telegram_locale, :string, default: "ru", null: false
  end
end
