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
      - if the user gives hours played, pass them in the hours argument
      - if the user wants to record score for an existing scheduled game, prefer passing game_id
      - admins can record historical or off-schedule matches without an existing game by passing team_a, team_b, score, and game_date
      - historical matches may be either 1v1 or 2v2
      - if one user message contains several completed match results, call record_match_stats once per result
      Do not ask for clarification if you already have enough info — just call the tool.
      Keep answers concise and helpful.

      When displaying opponents from find_opponent results, always show ALL of the following fields for each opponent:
      - name (telegram username or display name)
      - skill level
      - favorite courts (from the "favorite_courts" field, if present; otherwise skip)
      - games played (from the "games" field)
      - wins (from the "wins" field)
      - win percentage (from the "win_pct" field, show as "N/A" if null)
      Example format: "@username (уровень: beginner, любимые корты: Court A, Court B, игр: 10, побед: 7, винрейт: 70%%)"

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

    def chat(message, locale:, history: [], timeout_seconds: REQUEST_TIMEOUT)
      Ai::GeminiKeys.with_rotation(timeout_seconds: timeout_seconds, max_attempts: MAX_KEY_RETRIES) do |attempt|
        Rails.logger.info "[Ai::AssistantService] chat attempt=#{attempt} key_index=#{Ai::GeminiKeys.current_key_index} message=#{message.inspect}"

        chat = RubyLLM.chat(model: ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash"))
          .with_tool(Ai::Tools::FindOpponentTool.new(@user))
          .with_tool(Ai::Tools::FindCourtTool.new(@user))
          .with_tool(Ai::Tools::FindCoachTool.new(@user))
          .with_tool(Ai::Tools::RecordMatchStatsTool.new(@user))

        chat.with_instructions(SYSTEM_PROMPT % { locale: locale.to_s, user_info: user_info })
        hydrate_history(chat, history)
        response = chat.ask(message.to_s)
        Rails.logger.info "[Ai::AssistantService] response=#{response.content.to_s.truncate(200)}"
        response.content.to_s
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

    def hydrate_history(chat, history)
      Array(history).each do |entry|
        role = entry[:role] || entry["role"]
        content = entry[:content] || entry["content"]
        next unless %w[user assistant].include?(role.to_s)
        next if content.to_s.blank?

        chat.add_message(role: role.to_sym, content: content.to_s)
      end
    end
  end
end
