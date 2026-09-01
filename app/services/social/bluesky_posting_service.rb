require "net/http"
require "json"

module Social
  # AT Protocol: логинимся app-паролем, при необходимости заливаем блоб с
  # картинкой и создаём запись app.bsky.feed.post. Дев-программы у Bluesky нет —
  # аккаунт по email и App Password в настройках профиля.
  class BlueskyPostingService
    HOST = "https://bsky.social".freeze
    # Лимит поста — 300 графем (не байт и не символов).
    TEXT_LIMIT = 300
    # Блоб больше миллиона байт сервер отклоняет целиком, поэтому картинку
    # такого веса проще не прикладывать, чем потерять весь пост.
    MAX_BLOB_BYTES = 950_000
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    def self.configured?
      ENV["BLUESKY_IDENTIFIER"].to_s.strip.present? &&
        ENV["BLUESKY_APP_PASSWORD"].to_s.strip.present?
    end

    def initialize(content:, locale: :en)
      @content = content
      @locale = locale
    end

    # Возвращает at://-uri поста — по нему потом строится ссылка на него.
    def call
      return nil unless self.class.configured?

      session = create_session
      return nil unless session

      record = build_record(session)
      response = post_json(
        "com.atproto.repo.createRecord",
        { repo: session["did"], collection: "app.bsky.feed.post", record: record },
        token: session["accessJwt"]
      )
      return nil unless response

      response["uri"]
    rescue => e
      Rails.logger.error("[Social] bluesky post failed: #{e.class} #{e.message}")
      nil
    end

    private

    def text
      @text ||= @content.text(locale: @locale, limit: TEXT_LIMIT)
    end

    # accessJwt живёт недолго, но постов у нас единицы в день — дешевле логиниться
    # заново, чем городить refreshSession.
    def create_session
      post_json(
        "com.atproto.server.createSession",
        { identifier: ENV["BLUESKY_IDENTIFIER"], password: ENV["BLUESKY_APP_PASSWORD"] }
      )
    end

    def build_record(session)
      record = {
        "$type" => "app.bsky.feed.post",
        "text" => text,
        "createdAt" => Time.current.utc.iso8601,
        "langs" => [ @locale.to_s ]
      }

      facets = RichText.facets(text)
      record["facets"] = facets if facets.any?

      blob = upload_image(session)
      if blob
        record["embed"] = {
          "$type" => "app.bsky.embed.images",
          "images" => [ { "alt" => alt_text, "image" => blob } ]
        }
      end

      record
    end

    def alt_text
      text.lines.first.to_s.strip.presence || "GetCourt"
    end

    # Картинку контент отдаёт URL-ом, а Bluesky принимает сырые байты. Не
    # скачалась или слишком тяжёлая — постим без неё, но постим.
    def upload_image(session)
      url = @content.image_url
      return nil if url.blank?

      body, content_type = fetch_image(url)
      return nil unless body

      if body.bytesize > MAX_BLOB_BYTES
        Rails.logger.warn("[Social] bluesky image skipped: #{body.bytesize} bytes > #{MAX_BLOB_BYTES}")
        return nil
      end

      response = post_binary("com.atproto.repo.uploadBlob", body, content_type, token: session["accessJwt"])
      response && response["blob"]
    end

    def fetch_image(url)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.get(uri.request_uri)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Social] bluesky image fetch failed: #{response.code} #{url}")
        return nil
      end

      [ response.body, response["content-type"].presence || "image/png" ]
    rescue => e
      Rails.logger.warn("[Social] bluesky image fetch failed: #{e.class} #{e.message}")
      nil
    end

    def post_json(method, payload, token: nil)
      request = Net::HTTP::Post.new(endpoint(method))
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{token}" if token
      request.body = payload.to_json

      perform(request, method)
    end

    def post_binary(method, body, content_type, token:)
      request = Net::HTTP::Post.new(endpoint(method))
      request["Content-Type"] = content_type
      request["Authorization"] = "Bearer #{token}"
      request.body = body

      perform(request, method)
    end

    def endpoint(method)
      URI("#{HOST}/xrpc/#{method}")
    end

    def perform(request, method)
      uri = request.uri
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("[Social] bluesky #{method} failed: #{response.code} #{response.body.to_s.first(300)}")
        return nil
      end

      JSON.parse(response.body)
    rescue => e
      Rails.logger.error("[Social] bluesky #{method} failed: #{e.class} #{e.message}")
      nil
    end
  end
end
