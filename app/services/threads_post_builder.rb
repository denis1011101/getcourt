class ThreadsPostBuilder
  def initialize(game, locale:)
    @game = game
    @locale = locale
  end

  def text
    I18n.with_locale(@locale) do
      [
        I18n.t("games.threads.headline", sport: sport_label, city: city_name),
        "",
        I18n.t("games.threads.date_line", date: date_str, time: time_str),
        I18n.t("games.threads.court_line", court: @game.court&.name),
        I18n.t("games.threads.spots_line", count: spots_left),
        "",
        hashtags,
        "",
        game_url
      ].reject(&:blank?).join("\n")
    end
  end

  def image_url
    Rails.application.routes.url_helpers.game_share_card_url(@game, host: app_host, protocol: "https")
  end

  private

  def app_host
    ENV.fetch("APP_HOST")
  end

  def sport_label
    @game.sport.to_s
  end

  def city_name
    @game.court&.city_name.to_s
  end

  def hashtags
    tags = [ "#GetCourt" ]
    tags << "##{sport_label.gsub(/\s+/, '')}" if sport_label.present?
    tags << "##{city_name.gsub(/\s+/, '')}" if city_name.present?
    tags.join(" ")
  end

  def date_str
    date = @game.respond_to?(:next_date) ? (@game.next_date || @game.date) : @game.date
    date ? I18n.l(date.to_date, format: :long) : ""
  end

  def time_str
    @game.time&.strftime("%H:%M") || ""
  end

  def spots_left
    required = @game.players_count.to_i.positive? ? @game.players_count.to_i : 4
    approved = @game.participations.respond_to?(:approved) ? @game.participations.approved.count : 0
    [ required - approved, 0 ].max
  end

  def game_url
    Rails.application.routes.url_helpers.game_url(@game, host: app_host, protocol: "https")
  end
end
