module TennisScoreboard
  # Список главных турниров из config/major_tournaments.yml.
  module MajorTournaments
    PATH = Rails.root.join("config/major_tournaments.yml")

    def self.names
      @names ||= Array(YAML.safe_load_file(PATH)).map(&:to_s).reject(&:blank?).freeze
    end
  end
end
