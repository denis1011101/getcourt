require "timeout"

module Ai
  class AssistantService
    REQUEST_TIMEOUT = 30
    MAX_KEY_RETRIES = 3
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a tennis assistant for the GetCourt platform.
      You help users find opponents, courts, and games.
      Respond in the user's language (%{locale}).

      Current user info:
      %{user_info}

      Available tools: find_opponent, find_court, find_coach, record_match_stats.

      IMPORTANT: City names in the database are stored in English.
      Always translate city names to English before passing them to tools.
      For example: "Екатеринбург" → "Ekaterinburg", "Москва" → "Moscow", "Санкт-Петербург" → "Saint Petersburg".

      Use the user's city by default when no city is specified.
      When the user asks to find an opponent, immediately call the find_opponent tool.
      When the user asks to find a court, immediately call the find_court tool.
      When the user asks to find a coach or trainer, immediately call the find_coach tool.
      When the user asks to record match stats, match score, or match result, immediately call the record_match_stats tool.
      For record_match_stats:
      - pass team_a and team_b as comma-separated player names or telegram usernames
      - if the user refers to today's game, pass game_date: "today"
      - if the user gives an explicit date, pass it in a parseable format
      Do not ask for clarification if you already have enough info — just call the tool.
      Keep answers concise and helpful.

      When displaying opponents from find_opponent results, always show ALL of the following fields for each opponent:
      - name (telegram username or display name)
      - skill level
      - games played (from the "games" field)
      - wins (from the "wins" field)
      - win percentage (from the "win_pct" field, show as "N/A" if null)
      Example format: "@username (уровень: beginner, игр: 10, побед: 7, винрейт: 70%%)"

      When displaying courts from find_court results, always format each court as a list item:
      * Название (вид спорта: tennis) — https://getcourt.co/courts/1

      When displaying coaches from find_coach results, always show ALL of the following fields:
      - name (telegram username or display name)
      - bio (if present, otherwise skip)
      Example format: "@coach_name — Bio: experienced coach with 10 years..." (or just "@coach_name" if no bio)
    PROMPT

    def initialize(user)
      @user = user
    end

    def chat(message, locale:, timeout_seconds: REQUEST_TIMEOUT)
      attempts = 0
      Timeout.timeout(timeout_seconds) do
        begin
          attempts += 1
          Rails.logger.info "[Ai::AssistantService] chat attempt=#{attempts} key_index=#{self.class.current_key_index} message=#{message.inspect}"
          self.class.apply_current_key!

          chat = RubyLLM.chat(model: ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash"))
            .with_tool(Ai::Tools::FindOpponentTool.new(@user))
            .with_tool(Ai::Tools::FindCourtTool.new(@user))
            .with_tool(Ai::Tools::FindCoachTool.new(@user))
            .with_tool(Ai::Tools::RecordMatchStatsTool.new(@user))

          chat.with_instructions(SYSTEM_PROMPT % { locale: locale.to_s, user_info: user_info })
          response = chat.ask(message.to_s)
          Rails.logger.info "[Ai::AssistantService] response=#{response.content.to_s.truncate(200)}"
          response.content.to_s
        rescue RubyLLM::RateLimitError => e
          if attempts < [ MAX_KEY_RETRIES, self.class.api_keys.size ].min
            Rails.logger.warn "[Ai::AssistantService] rate limit on key ##{self.class.current_key_index}, rotating..."
            self.class.rotate_key!
            retry
          end
          raise
        end
      end
    end

    class << self
      def api_keys
        @api_keys ||= ENV.fetch("GEMINI_API_KEYS", ENV.fetch("GEMINI_API_KEY", ""))
          .split(",").map(&:strip).reject(&:empty?)
      end

      def current_key_index
        @current_key_index || 0
      end

      def rotate_key!
        @current_key_index = (current_key_index + 1) % api_keys.size
        apply_current_key!
      end

      def apply_current_key!
        return if api_keys.empty?

        RubyLLM.configure { |c| c.gemini_api_key = api_keys[current_key_index] }
      end
    end

    private

    def user_info
      return "Unknown user" unless @user

      parts = []
      parts << "Name: #{@user.name}" if @user.name.present?
      parts << "City: #{@user.city_name}" if @user.city_name.present?
      parts << "Skill level: #{@user.skill_level}" if @user.try(:skill_level).present?
      parts.join(", ")
    end
  end
end
