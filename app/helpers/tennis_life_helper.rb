module TennisLifeHelper
  def tennis_scoreboard_html(raw_text)
    text = raw_text.to_s
      .dup
      .force_encoding(Encoding::UTF_8)
      .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
    return if text.blank?

    normalized = text.gsub("\r\n", "\n")
    stop_at = normalized.index(/<b>\s*(Футбол|Хоккей|Баскетбол)\b/i)
    tennis_only = stop_at ? normalized[0...stop_at] : normalized
    return if tennis_only.blank?

    html = tennis_only.strip.gsub(/\n{2,}/, "\n\n").gsub("\n", "<br>")
    sanitize(html, tags: %w[b i br], attributes: [])
  end
end
