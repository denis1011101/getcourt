module Cities
  class SearchService
    RUSSIAN_MAP = {
      'а'=>'a','б'=>'b','в'=>'v','г'=>'g','д'=>'d','е'=>'e','ё'=>'e','ж'=>'zh','з'=>'z','и'=>'i','й'=>'y',
      'к'=>'k','л'=>'l','м'=>'m','н'=>'n','о'=>'o','п'=>'p','р'=>'r','с'=>'s','т'=>'t','у'=>'u','ф'=>'f',
      'х'=>'kh','ц'=>'ts','ч'=>'ch','ш'=>'sh','щ'=>'shch','ъ'=>'','ы'=>'y','ь'=>'','э'=>'e','ю'=>'yu','я'=>'ya'
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
        return t unless t.include?('?')
      rescue
      end

      s.chars.map { |ch| RUSSIAN_MAP[ch] || ch }.join
    end
  end
end
