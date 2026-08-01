class MakeTelegramLocaleNullable < ActiveRecord::Migration[8.1]
  def up
    change_column_null :users, :telegram_locale, true
    change_column_default :users, :telegram_locale, from: "ru", to: nil
    execute "UPDATE users SET telegram_locale = NULL WHERE telegram_locale = 'ru'"
  end

  def down
    execute "UPDATE users SET telegram_locale = 'ru' WHERE telegram_locale IS NULL"
    change_column_default :users, :telegram_locale, from: nil, to: "ru"
    change_column_null :users, :telegram_locale, false
  end
end
