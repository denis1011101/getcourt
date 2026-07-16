module Ai
  class TranslationService
    # Returns English translation of the given text using Gemini.
    # Returns nil if text is blank or translation fails.
    def self.translate_to_english(text)
      return nil if text.to_s.strip.blank?

      Ai::GeminiKeys.with_rotation do
        chat = RubyLLM.chat(model: ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash"))
        chat.ask(<<~PROMPT)
          Translate the following text to English. Return only the translation, no comments, no quotes.

          #{text}
        PROMPT
        .content
        .to_s
        .strip
        .presence
      end
    rescue RubyLLM::RateLimitError => e
      Rails.logger.error("[Ai::TranslationService] Rate limit on all keys: #{e.message}")
      nil
    rescue => e
      Rails.logger.error("[Ai::TranslationService] Translation failed: #{e.message}")
      nil
    end
  end
end
