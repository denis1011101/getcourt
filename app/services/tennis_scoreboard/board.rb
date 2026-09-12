module TennisScoreboard
  # Разобранное табло: турниры для карточек ленты и главный матч для главной.
  # Живёт на кэше сырого текста (Fetcher, 30 минут), своего кэша не держит.
  class Board
    Highlight = Struct.new(:tournament, :block, :match, keyword_init: true)

    def self.current
      new(Fetcher.tennis_block(Fetcher.raw_text))
    end

    attr_reader :tournaments

    def initialize(text)
      @tournaments = text.blank? ? [] : Parser.parse(text)
    end

    def empty?
      tournaments.empty?
    end

    def find(slug)
      tournaments.find { |tournament| tournament.slug == slug }
    end

    # Турнир, который стоит показать первым: тот, чей матч на главной, иначе
    # первый в гисте — он идёт в порядке значимости.
    def lead
      highlight&.tournament || tournaments.first
    end

    # Матч на главную: только с главных турниров. Раунда в гисте нет, но чем
    # ближе к финалу, тем короче список матчей на день — поэтому предпочитаем
    # идущий матч, затем турнир с самым коротким списком, затем ранний по
    # времени. Первую неделю шлема с шестнадцатью матчами на главную не тянем.
    def highlight
      return @highlight if defined?(@highlight)

      candidates = tournaments.select(&:major?).flat_map do |tournament|
        tournament.blocks.flat_map do |block|
          block.matches.select { |match| match.live? || match.scheduled? }
            .map { |match| Highlight.new(tournament: tournament, block: block, match: match) }
        end
      end

      @highlight = candidates
        .select { |candidate| candidate.block.matches.size <= LATE_ROUND_MATCHES }
        .min_by { |candidate| [ candidate.match.live? ? 0 : 1, candidate.block.matches.size, candidate.match.time.to_s ] }
    end

    # Полуфиналы и финал: два матча на тур в день, не больше.
    LATE_ROUND_MATCHES = 2
  end
end
