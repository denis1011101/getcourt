class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :api_tokens, :token, unique: true
    # Каждый запрос к /mcp сперва спрашивает, есть ли вообще живой токен, —
    # без индекса это чтение всей таблицы на каждом обращении.
    add_index :api_tokens, %i[revoked_at expires_at]
  end
end
