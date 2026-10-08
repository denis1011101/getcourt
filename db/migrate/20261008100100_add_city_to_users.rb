# Город пользователя ссылкой на справочник — рядом с city_name, который
# остаётся как есть. Страна определённого пользователя берётся из user.city.
class AddCityToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :city, foreign_key: { on_delete: :nullify }, index: true, null: true
  end
end
