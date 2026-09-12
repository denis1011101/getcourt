# Число игроков можно оставить «пока не выбрано». Значение по умолчанию (4)
# остаётся: уже созданные игры и бот его не теряют.
class MakeGamesPlayersCountOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :games, :players_count, true
  end
end
