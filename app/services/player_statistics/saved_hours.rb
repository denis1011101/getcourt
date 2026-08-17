module PlayerStatistics
  # Hours entered in the stats form land on every participant's entry, so any
  # entry from the game's current cycle carries the value the form shows back.
  module SavedHours
    module_function

    def for_game(game, user: nil)
      entry = entry_for(game, user)
      value = entry && hours_from(entry.data, game)

      if value.present?
        number = Float(value.to_s) rescue nil
        number && (number == number.round ? number.round : number)
      end
    end

    def entry_for(game, user)
      scope = PlayerStatisticEntry.where(game_id: game.id)
      cycle_start = game.respond_to?(:current_cycle_start) ? game.current_cycle_start : nil
      scope = scope.where("recorded_at >= ?", cycle_start) if cycle_start.present?

      entries = scope.order(recorded_at: :desc, id: :desc).to_a
      (user && entries.find { |entry| entry.user_id == user.id }) || entries.first
    end

    def hours_from(data, game)
      data = (data || {}).stringify_keys
      data[StatisticsPresenter.hours_field_for_game(game).to_s].presence ||
        data["singles_hours"].presence || data["doubles_hours"].presence
    end
  end
end
