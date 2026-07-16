require "timeout"

module Ai
  module GeminiKeys
    module_function

    def api_keys
      @api_keys ||= ENV.fetch("GEMINI_API_KEYS", ENV.fetch("GEMINI_API_KEY", ""))
        .split(",").map(&:strip).reject(&:empty?)
    end

    def current_key_index
      @current_key_index || 0
    end

    def rotate_key!
      return if api_keys.empty?

      @current_key_index = (current_key_index + 1) % api_keys.size
      apply_current_key!
    end

    def apply_current_key!
      return if api_keys.empty?

      RubyLLM.configure { |config| config.gemini_api_key = api_keys[current_key_index] }
    end

    def with_rotation(timeout_seconds: nil, max_attempts: 3, &operation)
      runner = lambda do
        attempts = 0

        begin
          attempts += 1
          apply_current_key!
          operation.call(attempts)
        rescue RubyLLM::RateLimitError
          raise unless attempts < [ max_attempts, api_keys.size ].min

          Rails.logger.warn "[Ai::GeminiKeys] rate limit on key ##{current_key_index}, rotating..."
          rotate_key!
          retry
        end
      end

      return runner.call unless timeout_seconds

      Timeout.timeout(timeout_seconds) { runner.call }
    end
  end
end
