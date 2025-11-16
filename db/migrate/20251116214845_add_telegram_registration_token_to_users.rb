class AddTelegramRegistrationTokenToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :telegram_registration_token, :string
    add_index  :users, :telegram_registration_token, unique: true
  end
end
