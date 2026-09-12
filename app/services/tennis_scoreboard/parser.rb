module TennisScoreboard
  # Разбирает теннисный блок гиста в турниры. Формат гиста:
  #
  #   <b>ATP - SINGLES, US Open (USA), hard</b>
  #   23:00 - 🇩🇪 <i>Zverev A.</i> - : - 🇺🇸 <i>Shelton B.</i>      ← ещё не начался
  #   Set 1 - <i>Sabalenka A.</i> 0 : 0 🇰🇿 <i>Rybakina E.</i>      ← идёт
  #
  # Один турнир в гисте — несколько блоков (ATP и WTA, одиночка и пары), в
  # карточке ленты они снова вместе. Строку, которая не разобралась, не теряем:
  # она остаётся в raw и уходит в вёрстку как есть, а в matches не попадает.
  class Parser
    Tournament = Struct.new(:slug, :name, :country, :blocks, :major, keyword_init: true) do
      alias_method :major?, :major

      def matches
        blocks.flat_map(&:matches)
      end

      # Текст блоков в исходной разметке гиста — его рисует та же вёрстка, что
      # и целое табло в классической версии.
      def raw
        blocks.map(&:raw).join("\n\n")
      end
    end

    Block = Struct.new(:tour, :discipline, :surface, :matches, :unparsed, :raw, keyword_init: true) do
      # Все ли строки блока разобраны: только тогда длине списка можно верить.
      def complete?
        unparsed.zero?
      end
    end

    Match = Struct.new(:status, :label, :time, :left, :right, :score, keyword_init: true) do
      def live?
        status == :live
      end

      def scheduled?
        status == :scheduled
      end

      # Минуты от начала суток, чтобы 9:00 стояло раньше 12:00, а не после.
      def minutes_of_day
        return nil unless time

        hours, minutes = time.split(":").map(&:to_i)
        hours * 60 + minutes
      end
    end

    Player = Struct.new(:flag, :name, keyword_init: true)

    HEADER = %r{\A<b>\s*(?<tour>[^-<]+?)\s*-\s*(?<discipline>[^,<]+?)\s*,\s*(?<name>.+?)\s*(?:\((?<country>[^)]*)\))?\s*,\s*(?<surface>[^<,]+?)\s*</b>\s*\z}
    LINE = %r{\A(?<label>.+?)\s+-\s+(?:(?<flag_left>\S+)\s+)?<i>(?<left>.+?)</i>\s+(?<score_left>\S+)\s*:\s*(?<score_right>\S+)\s+(?:(?<flag_right>\S+)\s+)?<i>(?<right>.+?)</i>\s*\z}
    TIME = /\A\d{1,2}:\d{2}\z/
    SET = /\Aset\s*\d+\z/i

    def self.parse(text, major_names: MajorTournaments.names)
      new(major_names).parse(text)
    end

    def initialize(major_names)
      @major_names = major_names.map(&:downcase)
    end

    def parse(text)
      tournaments = {}

      chunks(text).each do |lines|
        header = HEADER.match(lines.first) or next

        name = header[:name].strip
        country = header[:country].to_s.strip
        slug = "#{name} #{country}".parameterize
        tournament = tournaments[slug] ||= Tournament.new(
          slug: slug, name: name, country: country.presence, blocks: [],
          major: major?(name)
        )
        matches = lines.drop(1).filter_map { |line| parse_match(line) }
        tournament.blocks << Block.new(
          tour: header[:tour].strip,
          discipline: header[:discipline].strip,
          surface: header[:surface].strip,
          matches: matches,
          unparsed: lines.size - 1 - matches.size,
          raw: lines.join("\n")
        )
      end

      tournaments.values
    end

    private

    # Блок — заголовок и строки до пустой; заголовок узнаём по <b>, чтобы
    # пропущенная пустая строка между блоками не склеила два турнира.
    def chunks(text)
      text.to_s.gsub("\r\n", "\n").split("\n").map(&:strip).each_with_object([]) do |line, result|
        next if line.blank?

        result << [] if line.start_with?("<b>") || result.empty?
        result.last << line
      end
    end

    def parse_match(line)
      m = LINE.match(line) or return nil

      label = m[:label].strip
      status =
        if label.match?(TIME) then :scheduled
        elsif label.match?(SET) then :live
        else :finished
        end

      Match.new(
        status: status,
        label: label,
        time: (label if status == :scheduled),
        left: Player.new(flag: m[:flag_left], name: m[:left].strip),
        right: Player.new(flag: m[:flag_right], name: m[:right].strip),
        score: (status == :scheduled ? nil : "#{m[:score_left]}:#{m[:score_right]}")
      )
    end

    def major?(name)
      downcased = name.downcase
      @major_names.any? { |major| downcased.include?(major) }
    end
  end
end
