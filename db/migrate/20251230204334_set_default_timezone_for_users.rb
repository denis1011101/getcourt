class SetDefaultTimezoneForUsers < ActiveRecord::Migration[8.0]
  def up
    unless column_exists?(:users, :timezone)
      add_column :users, :timezone, :string, default: 'Asia/Yekaterinburg'
    end

    # гарантируем, что для существующих записей стоит значение
    execute <<~SQL
      UPDATE users
      SET timezone = 'Asia/Yekaterinburg'
      WHERE timezone IS NULL OR timezone = '';
    SQL

    change_column_default :users, :timezone, 'Asia/Yekaterinburg'
  end

  def down
    change_column_default :users, :timezone, nil
    remove_column :users, :timezone if column_exists?(:users, :timezone)
  end
end
