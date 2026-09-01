module Social
  module Content
    # Один пост в день, каждый раз другой. Материал берём из тех же источников,
    # что и лента Tennis Life, чтобы цифры наружу и на сайте не разъезжались.
    class Daily < Base
      VARIANTS = %w[upcoming result fact].freeze

      attr_reader :variant, :subject, :date

      def self.from_key(dedup_key)
        variant, subject, date = dedup_key.to_s.split(":", 3)
        return nil unless VARIANTS.include?(variant)
        return nil if subject.blank?

        new(variant: variant, subject: subject, date: Date.iso8601(date.to_s))
      rescue Date::Error
        nil
      end

      def initialize(variant:, subject:, date: Date.current)
        @variant = variant.to_s
        @subject = subject.to_s
        @date = date
      end

      def kind
        "daily"
      end

      # Дата в ключе, потому что один и тот же факт через месяц постить можно,
      # а дважды за день — нет.
      def dedup_key
        "#{variant}:#{subject}:#{date.iso8601}"
      end

      def available?
        case variant
        # Дата в ключе, а джоба могла отлежаться в очереди — «Tomorrow» должно
        # оставаться завтрашним днём, иначе анонс уйдёт задним числом.
        when "upcoming"
          game.present? && game.occurrence_date?(date + 1) && !game.cancelled_on?(date + 1) && game.spots_left.positive?
        when "result" then match.present? && winner_name.present?
        when "fact" then fact_ready?
        else false
        end
      end

      # Карточка игры уже рисуется для срочного поиска — переиспользуем. Факту и
      # результату картинки пока не рисуем: отдельный рендерер имеет смысл, когда
      # станет видно, что текстовые посты проседают по охвату.
      def image_url
        return nil unless variant == "upcoming" && game

        Rails.application.routes.url_helpers.game_share_card_url(game, host: Social.app_host, protocol: "https")
      end

      def geo
        return nil unless variant == "upcoming" && game

        lat, lng = game.court&.coordinates_pair
        return nil unless lat && lng

        { lat: lat, lng: lng, label: [ game.court&.name, game.court&.city_name.presence ].compact.join(", ") }
      end

      private

      def body(locale:)
        I18n.with_locale(locale) do
          case variant
          when "upcoming" then upcoming_text
          when "result" then result_text
          when "fact" then fact_text
          end
        end
      end

      def upcoming_text
        I18n.t(
          "social.daily.upcoming",
          sport: game.sport.presence || I18n.t("games.sports.tennis"),
          court: game.court&.name,
          city: game.court&.city_name,
          time: game.time&.strftime("%H:%M"),
          count: game.spots_left,
          url: Rails.application.routes.url_helpers.game_url(game, host: Social.app_host, protocol: "https")
        )
      end

      def result_text
        I18n.t(
          "social.daily.result",
          score: match.score,
          surface: surface_label,
          winner: winner_name,
          url: Social.app_url
        )
      end

      def fact_text
        I18n.t("social.daily.fact.#{subject}", **fact_interpolations)
      end

      def game
        return @game if defined?(@game)

        @game = variant == "upcoming" ? Game.find_by(id: subject) : nil
      end

      def match
        return @match if defined?(@match)

        @match = variant == "result" ? Match.where.not(score: [ nil, "" ]).find_by(id: subject) : nil
      end

      def fact
        return @fact if defined?(@fact)

        @fact =
          if variant == "fact" && TennisLife::Feed::Sources::Facts::KEYS.include?(subject)
            TennisLife::Feed::Sources::Facts.resolve([ subject ], snapshot_ts: Time.current)[subject]
          end
      end

      def surface_label
        return I18n.t("social.daily.unknown_surface") if match.surface.blank?

        I18n.t("courts.surfaces.#{match.surface}", default: match.surface.to_s.tr("_", " ").capitalize)
      end

      # Ничьи и матчи без известного соперника постить нечем — «X takes it» про
      # них соврёт, поэтому такой материал считается отсутствующим.
      def winner
        return nil unless match

        case match.outcome
        when "win" then match.user
        when "loss" then match.opponent
        end
      end

      def winner_name
        Names.short(winner&.name).presence
      end

      # Пустой факт («0 hours played») хуже молчания, поэтому у каждого ключа своё
      # условие содержательности.
      def fact_ready?
        payload = fact
        return false if payload.blank?

        case subject
        when "total_hours" then payload[:value].to_f.positive?
        when "courts_cities" then payload[:courts].to_i.positive?
        when "longest_match" then payload[:score].present?
        when "popular_surface" then payload[:surface].present?
        when "player_month" then payload[:name].present? && payload[:count].to_i.positive?
        when "new_players_month" then payload[:count].to_i.positive?
        when "busiest_court" then payload[:name].present? && payload[:count].to_i.positive?
        else false
        end
      end

      def fact_interpolations
        payload = fact.to_h

        case subject
        when "total_hours" then { value: payload[:value] }
        when "courts_cities" then { courts: payload[:courts], cities: payload[:cities] }
        when "longest_match" then { score: payload[:score], games: payload[:games] }
        when "popular_surface"
          { surface: I18n.t("courts.surfaces.#{payload[:surface]}", default: payload[:surface].to_s), count: payload[:count] }
        when "player_month" then { name: Names.short(payload[:name]), count: payload[:count] }
        when "new_players_month" then { count: payload[:count] }
        when "busiest_court" then { name: payload[:name], count: payload[:count] }
        else {}
        end
      end
    end
  end
end
