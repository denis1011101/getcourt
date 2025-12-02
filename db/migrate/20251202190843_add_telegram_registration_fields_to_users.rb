class AddTelegramRegistrationFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :registration_source, :string
    add_column :users, :telegram_generated_email, :boolean, default: false, null: false
    add_index :users, :registration_source
  end
end
