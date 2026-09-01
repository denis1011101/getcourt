module Social
  module Content
    # Анонс срочного поиска игроков. Переехал из ThreadsPostBuilder: текст
    # площадко-независим, так что жить ему в контенте, а не в адаптере.
    class UrgentSearch < Base
      def self.from_key(dedup_key)
        game_id = dedup_key.to_s[/\Agame:(\d+)\z/, 1]
        return nil unless game_id

        game = Game.find_by(id: game_id)
        game && new(game)
      end

      def initialize(game)
        @game = game
      end

      def kind
        "urgent"
      end

      def dedup_key
        "game:#{@game.id}"
      end

      # Пока джоба стоит в очереди, поиск могли выключить — постить уже нечего.
      def available?
        @game.persisted? && @game.urgent_player_search?
      end

      def image_url
        Rails.application.routes.url_helpers.game_share_card_url(@game, host: Social.app_host, protocol: "https")
      end

      def geo
        lat, lng = @game.court&.coordinates_pair
        return nil unless lat && lng

        { lat: lat, lng: lng, label: [ @game.court&.name, city_name.presence ].compact.join(", ") }
      end

      def calendar
        starts_at = @game.start_at_for_ui
        return nil unless starts_at

        {
          title: I18n.t("social.urgent.headline", sport: sport_label, city: city_name, locale: :en),
          starts_at: starts_at,
          ends_at: starts_at + (@game.duration_minutes.to_i.positive? ? @game.duration_minutes.to_i : 60).minutes,
          location: geo&.dig(:label)
        }
      end

      private

      def body(locale:)
        I18n.with_locale(locale) do
          [
            I18n.t("social.urgent.headline", sport: sport_label, city: city_name),
            "",
            I18n.t("social.urgent.date_line", date: date_str, time: time_str),
            I18n.t("social.urgent.court_line", court: @game.court&.name),
            I18n.t("social.urgent.spots_line", count: spots_left),
            "",
            hashtags,
            "",
            game_url
          ].reject(&:blank?).join("\n").gsub(/ {2,}/, " ")
        end
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
        date = @game.next_date || @game.date
        date ? I18n.l(date.to_date, format: :long) : ""
      end

      def time_str
        @game.time&.strftime("%H:%M") || ""
      end

      def spots_left
        [ @game.spots_left, 0 ].max
      end

      def game_url
        Rails.application.routes.url_helpers.game_url(@game, host: Social.app_host, protocol: "https")
      end
    end
  end
end
