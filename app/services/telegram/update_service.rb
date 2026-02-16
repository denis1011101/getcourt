module Telegram
  class UpdateService
    def self.process(update)
      new(update).process
    end

    def initialize(update, logger = defined?(Rails) ? Rails.logger : Logger.new($stdout))
      @update = (update || {}).dup
      @logger = logger
    end

    def process
      if message
        @logger.info "[Telegram::UpdateService] message from #{message.dig('from', 'id')}: #{message['text'].to_s.inspect}"
        Telegram::Processors::MainMenuProcessor.process_update(@update)
      elsif @update["callback_query"]
        @logger.info "[Telegram::UpdateService] callback from #{callback.dig('from', 'id')}: #{callback['data'].inspect}"
        Telegram::Handlers::CallbackHandler.process(callback)
      else
        @logger.debug "[Telegram::UpdateService] unsupported update types: #{@update.keys.inspect}"
      end
    rescue => e
      @logger.error "[Telegram::UpdateService] error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
    end

    private

    def message
      @update["message"] || @update["edited_message"]
    end

    def callback
      @update["callback_query"]
    end
  end
end
