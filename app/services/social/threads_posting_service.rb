require "net/http"
require "json"

module Social
  # Meta Graph API в два шага: контейнер -> публикация. Кода это не меняет: токен
  # из дев-программы Meta из РФ пока не получить, поэтому адаптер просто молчит,
  # пока в окружении нет ключей.
  class ThreadsPostingService
    HOST = "https://graph.threads.net".freeze
    VERSION = "v1.0".freeze
    TEXT_LIMIT = 500

    def self.configured?
      ENV["THREADS_ACCESS_TOKEN"].to_s.strip.present? &&
        ENV["THREADS_USER_ID"].to_s.strip.present?
    end

    def initialize(content:, locale: :en)
      @content = content
      @locale = locale
    end

    def call
      return nil unless self.class.configured?

      creation_id = create_container
      return nil unless creation_id

      publish(creation_id)
    end

    private

    def text
      @text ||= @content.text(locale: @locale, limit: TEXT_LIMIT)
    end

    def create_container
      params = { text: text, access_token: ENV["THREADS_ACCESS_TOKEN"] }
      if @content.image_url.present?
        params[:media_type] = "IMAGE"
        params[:image_url] = @content.image_url
      else
        params[:media_type] = "TEXT"
      end

      response = Net::HTTP.post_form(URI("#{HOST}/#{VERSION}/#{ENV['THREADS_USER_ID']}/threads"), params)
      JSON.parse(response.body)["id"]
    rescue => e
      Rails.logger.error("[Social] threads create_container failed: #{e.class} #{e.message}")
      nil
    end

    def publish(creation_id)
      response = Net::HTTP.post_form(
        URI("#{HOST}/#{VERSION}/#{ENV['THREADS_USER_ID']}/threads_publish"),
        creation_id: creation_id,
        access_token: ENV["THREADS_ACCESS_TOKEN"]
      )
      JSON.parse(response.body)["id"]
    rescue => e
      Rails.logger.error("[Social] threads publish failed: #{e.class} #{e.message}")
      nil
    end
  end
end
