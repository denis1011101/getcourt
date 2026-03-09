class MakeUsersCoachNullable < ActiveRecord::Migration[8.0]
  def up
    change_column_null :users, :coach, true
    change_column_default :users, :coach, nil
  end

  def down
    # restore existing NULLs to false before adding constraint back
    User.where(coach: nil).update_all(coach: false)
    change_column_default :users, :coach, false
    change_column_null :users, :coach, false
  end
end
