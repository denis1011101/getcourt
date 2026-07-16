require "json"
require "ruby_llm/schema"

module Ai
  class ScoreFromPhotoService
    REQUEST_TIMEOUT = 30
    MAX_KEY_RETRIES = 3
    MAX_SETS = 5

    PROMPT = <<~PROMPT.freeze
      Extract one racket-sport match score from this image.
      Read the scoreboard rows as top and bottom. Return game scores for each set in order.
      For a 7-6 or 6-7 set, put the tiebreak points on the row that lost the set when visible.
      Extract player names into top_names and bottom_names only when their row is clear.
      Do not guess unreadable numbers or names. If no single match score can be recognized, return empty sets.
    PROMPT

    class ScoreSchema < RubyLLM::Schema
      array :sets, min_items: 0, max_items: MAX_SETS do
        object do
          integer :top, minimum: 0, maximum: 99
          integer :bottom, minimum: 0, maximum: 99
          integer :tiebreak_top, minimum: 0, maximum: 99, required: false
          integer :tiebreak_bottom, minimum: 0, maximum: 99, required: false
        end
      end
      array :top_names, of: :string
      array :bottom_names, of: :string
    end

    def call(photo_path, timeout_seconds: REQUEST_TIMEOUT)
      Ai::GeminiKeys.with_rotation(timeout_seconds: timeout_seconds, max_attempts: MAX_KEY_RETRIES) do
        response = RubyLLM.chat(model: ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash"))
          .with_schema(ScoreSchema)
          .ask(PROMPT, with: photo_path)
        normalize(response.content)
      end
    end

    private

    def normalize(content)
      content = JSON.parse(content) if content.is_a?(String)
      content = hash_from(content)

      {
        sets: Array(content["sets"] || content[:sets]).first(MAX_SETS).filter_map { |set| normalize_set(set) },
        top_names: normalize_names(content["top_names"] || content[:top_names]),
        bottom_names: normalize_names(content["bottom_names"] || content[:bottom_names])
      }
    end

    def normalize_set(set)
      set = hash_from(set)
      top = integer(set["top"] || set[:top])
      bottom = integer(set["bottom"] || set[:bottom])
      return if top.nil? || bottom.nil?

      result = { top: top, bottom: bottom }
      tiebreak_top = integer(set["tiebreak_top"] || set[:tiebreak_top])
      tiebreak_bottom = integer(set["tiebreak_bottom"] || set[:tiebreak_bottom])
      result[:tiebreak_top] = tiebreak_top unless tiebreak_top.nil?
      result[:tiebreak_bottom] = tiebreak_bottom unless tiebreak_bottom.nil?
      result
    end

    def normalize_names(names)
      Array(names).filter_map do |name|
        value = name.to_s.strip
        value if value.present?
      end
    end

    def hash_from(value)
      return value if value.is_a?(Hash)

      value.to_h
    rescue TypeError, NoMethodError
      {}
    end

    def integer(value)
      number = Integer(value, exception: false)
      number if number&.between?(0, 99)
    end
  end
end
