class StatisticsPresenter
  FIELDS = [
    { key: :singles_hours,           label: "Singles hours",               example: "1.5" },
    { key: :doubles_hours,           label: "Doubles hours",               example: "2.0" },
    { key: :singles_games,           label: "Singles matches",             example: "3" },
    { key: :doubles_games,           label: "Doubles matches",             example: "3" },
    { key: :aces,                    label: "Aces",                        example: "5" },
    { key: :double_faults,           label: "Double faults",               example: "2" },
    { key: :break_points_saved,      label: "Break points saved",          example: "3" },
    { key: :break_points_converted,  label: "Break points converted",      example: "2" },
    { key: :winners,                 label: "Winners",                     example: "15" },
    { key: :unforced_errors,         label: "Unforced errors",             example: "8" },
    { key: :net_points_won,          label: "Net points won",              example: "6" },
    { key: :service_points_won,      label: "Service points won",          example: "20" },
    { key: :return_points_won,       label: "Return points won",           example: "12" },
    { key: :return_games_won,        label: "Games won on return",         example: "4" },
    { key: :games_won_total,         label: "Total games won",             example: "12" }
  ].freeze

  class << self
    def fields = FIELDS

    def field_def(field)
      FIELDS.find { |f| f[:key].to_s == field.to_s }
    end

    def field_example(field)
      field_def(field)&.fetch(:example, nil) || "1"
    end

    def field_type(field)
      PlayerStatistic.numeric_field_type(field)
    end

    def allowed_keys
      @allowed_keys ||= FIELDS.map { |f| f[:key].to_s }.freeze
    end

    # Telegram UX: user enters only "hours".
    # We map hours into singles_hours (2 players) or doubles_hours (4+ players).
    def hours_field_for_game(game)
      count = stats_players_count(game)
      count >= 4 ? :doubles_hours : :singles_hours
    end

    def hours_label_for_game(game)
      hours_field_for_game(game) == :doubles_hours ? "Hours (doubles)" : "Hours (singles)"
    end

    private

    def stats_players_count(game)
      return game.players_count.to_i if game.respond_to?(:players_count) && game.players_count.to_i.positive?

      users = []
      users << game.user if game.respond_to?(:user)
      if game.respond_to?(:participations)
        users.concat(game.participations.includes(:user).map(&:user))
      end
      users.compact.uniq { |u| u.id }.size
    rescue
      2
    end
  end
end
