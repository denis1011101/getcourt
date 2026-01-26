class StatisticsPresenter
  FIELDS = [
    { key: :singles_hours,    label: "Singles hours",    example: "1.5" },
    { key: :doubles_hours,    label: "Doubles hours",    example: "2.0" }
    # { key: :singles_sessions, label: "Singles sessions", example: "1" },
    # { key: :doubles_sessions, label: "Doubles sessions", example: "1" },
    # { key: :singles_games,    label: "Singles matches",  example: "3" },
    # { key: :doubles_games,    label: "Doubles matches",  example: "3" },
    # { key: :singles_wins,     label: "Singles wins",     example: "2" },
    # { key: :singles_losses,   label: "Singles losses",   example: "1" },
    # { key: :doubles_wins,     label: "Doubles wins",     example: "2" },
    # { key: :doubles_losses,   label: "Doubles losses",   example: "1" }
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
  end
end
