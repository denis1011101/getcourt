module Social
  # Текст поста площадко-независим, а вот его разметка — нет. Здесь и усечение
  # (Bluesky считает графемы), и facets (Bluesky считает БАЙТЫ UTF-8 — главный
  # источник багов, если брать офсеты из String#index).
  module RichText
    TAG_PATTERN = /(?:\A|(?<=\s))#[^\s#]+/
    LINK_PATTERN = %r{https?://[^\s<>()\[\]"']+}
    TRAILING_PUNCTUATION = /[.,;:!?)\]}»"']+\z/
    ELLIPSIS = "…".freeze

    class << self
      def grapheme_length(text)
        text.to_s.scan(/\X/).size
      end

      def truncate(text, limit)
        text = text.to_s
        return text if limit.nil?

        graphemes = text.scan(/\X/)
        return text if graphemes.size <= limit

        kept = graphemes.first([ limit - 1, 0 ].max).join.rstrip
        "#{kept}#{ELLIPSIS}"
      end

      # Ссылки и хэштеги для app.bsky.feed.post. Без facets ссылка останется голым
      # текстом: Threads кликал её сам, Bluesky — нет.
      def facets(text)
        text = text.to_s
        links = collect(text, LINK_PATTERN)
        link_ranges = links.map { |value, start| start...(start + value.length) }

        facets = links.map do |value, start|
          facet(text, start, value, "$type" => "app.bsky.richtext.facet#link", "uri" => value)
        end

        collect(text, TAG_PATTERN).each do |value, start|
          next if link_ranges.any? { |range| range.cover?(start) }
          next if value.length <= 1

          facets << facet(text, start, value, "$type" => "app.bsky.richtext.facet#tag", "tag" => value.delete_prefix("#"))
        end

        facets.sort_by { |facet| facet["index"]["byteStart"] }
      end

      private

      # Возвращает пары [значение без хвостовой пунктуации, офсет в символах].
      def collect(text, pattern)
        result = []
        position = 0

        while (match = pattern.match(text, position))
          value = match[0].sub(TRAILING_PUNCTUATION, "")
          result << [ value, match.begin(0) ] unless value.empty?
          position = match.end(0)
          position += 1 if match.end(0) == match.begin(0)
        end

        result
      end

      def facet(text, start_char, value, feature)
        byte_start = text[0...start_char].bytesize

        {
          "index" => { "byteStart" => byte_start, "byteEnd" => byte_start + value.bytesize },
          "features" => [ feature ]
        }
      end
    end
  end
end
