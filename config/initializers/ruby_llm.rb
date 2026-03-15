RubyLLM.configure do |config|
  keys = ENV.fetch("GEMINI_API_KEYS", ENV.fetch("GEMINI_API_KEY", ""))
    .split(",").map(&:strip).reject(&:empty?)
  config.gemini_api_key = keys.first if keys.any?
end
