class CreateOutreachContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :outreach_contacts do |t|
      t.string :email, null: false
      t.string :name
      t.datetime :sent_at
      t.datetime :unsubscribed_at
      t.datetime :reserved_at
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.timestamps
    end

    add_index :outreach_contacts, :email, unique: true
    # Очередь выбирается по «ещё не отправляли и никем не занято», и это
    # единственный запрос к таблице — без индекса он читает весь список целиком.
    add_index :outreach_contacts, %i[sent_at unsubscribed_at attempts reserved_at]
    # Дневной остаток считается по обоим датам сразу, каждая под своим индексом.
    add_index :outreach_contacts, :reserved_at
  end
end
