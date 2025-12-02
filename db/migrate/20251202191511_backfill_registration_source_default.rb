class BackfillRegistrationSourceDefault < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Backfill registration_source -> 'email' for existing users" do
      execute <<~SQL.squish
        UPDATE users
        SET registration_source = 'email'
        WHERE registration_source IS NULL OR registration_source = ''
      SQL
    end

    change_column_default :users, :registration_source, from: nil, to: "email"
    change_column_null :users, :registration_source, false
  end

  def down
    change_column_null :users, :registration_source, true
    change_column_default :users, :registration_source, from: "email", to: nil
    execute <<~SQL.squish
      UPDATE users
      SET registration_source = NULL
      WHERE registration_source = 'email' AND telegram_generated_email = false
    SQL
  end
end
