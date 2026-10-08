# Устойчивая ссылка корта на запись справочника рядом со строковым city_name.
# Связь необязательна: район, неоднозначное или не найденное название
# оставляют city_id пустым; исчезнувшая запись справочника тоже обнуляет связь
# (on_delete: :nullify), а не блокирует удаление. Страна живёт отдельно — её
# геокодер знает и тогда, когда город определить не удалось. Данные здесь не
# трогаем: заполнение — дело геокодинга и отдельного backfill.
class AddCityAndCountryToCourts < ActiveRecord::Migration[8.1]
  def change
    add_reference :courts, :city, foreign_key: { on_delete: :nullify }, index: true, null: true
    add_column :courts, :country_code, :string, limit: 2
  end
end
