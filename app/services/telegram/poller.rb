module Telegram
  class Poller
    require "net/http"
    require "uri"
    require "json"

    def initialize(token = ENV["TELEGRAM_BOT_TOKEN"], logger = Rails.logger)
      @token = token.to_s
      @logger = logger
      @offset = nil
      raise "TELEGRAM_BOT_TOKEN not set" if @token.empty?
    end

    # Поллер попадает в логи и в сообщения об ошибках целиком, поэтому в inspect
    # оставляем только позицию в очереди обновлений — токен бота светить нельзя.
    private def instance_variables_to_inspect = [ :@offset ]

    # Single poll iteration: fetch updates and dispatch to UpdateService
    def run_once(poll_interval: 0.5)
      updates = fetch_updates(@offset)
      Array(updates).each do |u|
        begin
          @offset = [ @offset.to_i, u["update_id"].to_i + 1 ].max
          Telegram::UpdateService.process(u)
        rescue => e
          @logger.error "[Telegram::Poller] dispatch error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        end
      end
      sleep(poll_interval) if poll_interval && poll_interval > 0
    rescue => e
      @logger.error "[Telegram::Poller] run_once error: #{e.class}: #{e.message}"
      sleep 1
    end

    # Continuous loop (blocking)
    def run_loop(poll_interval: 1)
      @logger.info "[Telegram::Poller] starting loop (interval=#{poll_interval})"
      loop { run_once(poll_interval: poll_interval) }
    end

    # delegate single-request API calls to Telegram::Api
    def send_api(method, params = {})
      Telegram::Api.send_api(method, params)
    end

    private

    def fetch_updates(offset)
      uri = URI("https://api.telegram.org/bot#{@token}/getUpdates")
      params = {}
      params[:offset] = offset if offset && offset > 0
      params[:timeout] = 20
      uri.query = URI.encode_www_form(params)

      res = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30, open_timeout: 5) do |http|
        res = http.get(uri.request_uri)
      end
      body = res.body.to_s
      json = JSON.parse(body) rescue nil
      unless json && json["ok"]
        @logger.warn "[Telegram::Poller] getUpdates failed: #{body.inspect}"
        return []
      end
      json["result"] || []
    rescue => e
      @logger.error "[Telegram::Poller] fetch_updates error: #{e.class}: #{e.message}"
      []
    end
  end
end
