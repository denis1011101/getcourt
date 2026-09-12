# Корт можно выбрать позже: игру объявляют, когда ещё не знают, где играют.
class MakeGamesCourtOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :games, :court_id, true
  end
end
