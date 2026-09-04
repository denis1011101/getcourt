module Social
  # Nostr: регистрации нет вообще, есть ключевая пара. Событие подписывается и
  # уходит сразу на несколько релеев — отказы отдельных релеев игнорируем, пост
  # считается опубликованным, если его принял хоть один.
  class NostrPostingService
    # Список проверен 05.09.2026 запросом NIP-11 с прод-машины: у всех пятерых
    # запись открыта, без оплаты и без AUTH. Отсюда убраны nostr.wine (пишет
    # только за деньги, отвечал `restricted`) и relay.nostr.band (агрегатор,
    # с нашего хоста не отвечает вовсе).
    DEFAULT_RELAYS = %w[
      wss://relay.damus.io
      wss://nos.lol
      wss://relay.primal.net
      wss://offchain.pub
      wss://nostr.mom
    ].freeze

    # Лимита на длину заметки в протоколе нет.
    TEXT_LIMIT = nil
    PROFILE_KIND = 0
    NOTE_KIND = 1
    CALENDAR_KIND = 31923

    PROFILE_ABOUT = "Free service for finding tennis, padel, table tennis and squash partners. " \
                    "Find courts near you, join a game or gather your own, track matches and your rating.".freeze

    class << self
      def configured?
        secret_key.present?
      end

      # Принимаем и hex, и nsec1... — в настройках клиентов копируют обычно второе.
      # Кривой ключ здесь же и отсеиваем: иначе он всплыл бы уже при подписи.
      def secret_key
        raw = ENV["NOSTR_SECRET_KEY"].to_s.strip
        return nil if raw.blank?

        key = raw.start_with?("nsec1") ? Nostr::Bech32.decode(raw).last : [ raw.delete_prefix("0x") ].pack("H*")
        return key if key.bytesize == 32

        Rails.logger.error("[Social] nostr key must be 32 bytes, got #{key.bytesize}")
        nil
      rescue Nostr::Bech32::Error => e
        Rails.logger.error("[Social] nostr key is unusable: #{e.message}")
        nil
      end

      def relays
        configured = ENV["NOSTR_RELAYS"].to_s.split(",").map(&:strip).reject(&:blank?)
        configured.presence || DEFAULT_RELAYS
      end

      # Профиль — такое же подписанное событие, только kind 0: пока его нет,
      # клиенты подписывают аккаунт голым hex-ключом. Событие заменяемое, релей
      # хранит лишь последнее, поэтому таску можно гонять сколько угодно —
      # дублей не будет, а смена названия или картинки просто перезапишет старое.
      def publish_profile
        return nil unless configured?

        event = Nostr::Event.new(kind: PROFILE_KIND, content: profile_content, secret_key: secret_key)
        broadcast(event) ? event.id : nil
      rescue => e
        # Длину ключа `configured?` проверяет, а вот годится ли он как скаляр
        # secp256k1 — выясняется только при подписи. Таска должна сказать об
        # этом строкой, а не полотном трейса.
        Rails.logger.error("[Social] nostr profile failed: #{e.class} #{e.message}")
        nil
      end

      def broadcast(event)
        accepted = relays.count { |url| Nostr::Relay.new(url).publish(event) }

        Rails.logger.info("[Social] nostr event #{event.id} accepted by #{accepted}/#{relays.size} relays")
        accepted.positive?
      end

      private

      # name — короткий ник, display_name — то, что видно крупно. Аккаунт
      # англоязычный, как и все остальные площадки.
      def profile_content
        JSON.generate(
          "name" => "getcourt",
          "display_name" => "GetCourt",
          "about" => PROFILE_ABOUT,
          "picture" => Social.logo_url,
          "website" => Social.app_url
        )
      end
    end

    def initialize(content:, locale: :en)
      @content = content
      @locale = locale
    end

    # Возвращает id заметки (kind 1) — по нему пост находится в любом клиенте.
    def call
      return nil unless self.class.configured?

      note = build_note
      return nil unless broadcast(note)

      # Календарное событие видно только календарным клиентам, поэтому его
      # неудача не отменяет обычную заметку.
      broadcast(build_calendar_event) if @content.calendar

      note.id
    rescue => e
      Rails.logger.error("[Social] nostr post failed: #{e.class} #{e.message}")
      nil
    end

    private

    def text
      @text ||= @content.text(locale: @locale, limit: TEXT_LIMIT)
    end

    # Клиенты разворачивают картинку по голой ссылке в тексте — отдельного поля
    # для медиа в kind 1 нет.
    def note_content
      image = @content.image_url
      image.present? ? "#{text}\n\n#{image}" : text
    end

    def build_note
      Nostr::Event.new(
        kind: NOTE_KIND,
        content: note_content,
        tags: note_tags,
        secret_key: secret_key
      )
    end

    def build_calendar_event
      calendar = @content.calendar

      tags = [
        # d делает событие адресуемым: повторная публикация того же матча
        # заменит запись, а не размножит её.
        [ "d", "#{@content.kind}-#{@content.dedup_key}" ],
        [ "title", calendar[:title].to_s ],
        [ "start", calendar[:starts_at].to_i.to_s ],
        [ "end", calendar[:ends_at].to_i.to_s ]
      ]
      tags << [ "location", calendar[:location] ] if calendar[:location].present?
      tags.concat(geohash_tags)

      Nostr::Event.new(
        kind: CALENDAR_KIND,
        content: text,
        tags: tags,
        secret_key: secret_key
      )
    end

    def secret_key
      @secret_key ||= self.class.secret_key
    end

    def note_tags
      tags = RichText.facets(text).filter_map do |facet|
        feature = facet["features"].first
        [ "t", feature["tag"].downcase ] if feature["$type"].end_with?("#tag")
      end.uniq

      tags.concat(geohash_tags)
      tags << [ "location", geo[:label] ] if geo && geo[:label].present?
      tags
    end

    def geo
      @content.geo
    end

    def geohash_tags
      return [] unless geo

      Nostr::Geohash.prefixes(geo[:lat], geo[:lng]).map { |prefix| [ "g", prefix ] }
    end

    def broadcast(event)
      self.class.broadcast(event)
    end
  end
end
