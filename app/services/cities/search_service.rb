module Cities
  class SearchService
    RUSSIAN_MAP = {
      "\u0430"=>"a", "\u0431"=>"b", "\u0432"=>"v", "\u0433"=>"g", "\u0434"=>"d", "\u0435"=>"e", "\u0451"=>"e", "\u0436"=>"zh", "\u0437"=>"z", "\u0438"=>"i", "\u0439"=>"y",
      "\u043A"=>"k", "\u043B"=>"l", "\u043C"=>"m", "\u043D"=>"n", "\u043E"=>"o", "\u043F"=>"p", "\u0440"=>"r", "\u0441"=>"s", "\u0442"=>"t", "\u0443"=>"u", "\u0444"=>"f",
      "\u0445"=>"kh", "\u0446"=>"ts", "\u0447"=>"ch", "\u0448"=>"sh", "\u0449"=>"shch", "\u044A"=>"", "\u044B"=>"y", "\u044C"=>"", "\u044D"=>"e", "\u044E"=>"yu", "\u044F"=>"ya"
    }.freeze

    def initialize(query:, country: nil, limit: 20)
      @query = query.to_s.strip
      @country = country
      @limit = limit.to_i
    end

    def call
      return City.none if @query.empty?

      q = @query.downcase
      translit = transliterate_russian(q)

      pattern_orig = "%#{q}%"
      pattern_trans = "%#{translit}%"

      relation = City.where(
        "(lower(name) LIKE ? OR lower(asciiname) LIKE ? OR lower(name) LIKE ? OR lower(asciiname) LIKE ?)",
        pattern_orig, pattern_orig, pattern_trans, pattern_trans
      )
      relation = relation.where(country_code: @country) if @country.present?
      relation.order(population: :desc).limit(@limit)
    end

    private

    def transliterate_russian(str)
      s = str.to_s.dup
      s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "") rescue s.force_encoding("UTF-8")
      begin
        t = I18n.transliterate(s)
        return t unless t.include?("?")
      rescue
      end

      s.chars.map { |ch| RUSSIAN_MAP[ch] || ch }.join
    end
  end
end
