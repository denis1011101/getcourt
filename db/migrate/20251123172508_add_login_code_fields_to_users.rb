class AddLoginCodeFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :login_code, :string
    add_column :users, :login_code_sent_at, :datetime
    add_column :users, :login_via, :string
    add_index :users, :login_code
  end
end
