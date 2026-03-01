module TennisLifeHelper
  def tennis_scoreboard_html(raw_text)
    tennis_only = TennisScoreboard::Fetcher.tennis_block(raw_text)
    return if tennis_only.blank?

    html = tennis_only.strip.gsub(/\n{2,}/, "\n\n").gsub("\n", "<br>")
    sanitize(html, tags: %w[b i br], attributes: [])
  end
end
