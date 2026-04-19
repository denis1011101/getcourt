module Ai
  module Tools
    class RecordMatchStatsTool < RubyLLM::Tool
      description "Record match score for a game. Admins can also record off-schedule historical matches without an existing game."
      param :game_id, desc: "ID of the game to record stats for", required: false
      param :game_date, desc: "Game date, for example 'today' or '2026-03-24'", required: false
      param :game_time, desc: "Game start time, for example '19:00'", required: false
      param :score, desc: 'Match score, for example "6-2 6-3"', required: true
      param :hours, desc: 'Hours played, for example "1.5"', required: false
      param :team_a, desc: "Comma-separated player names or telegram usernames for team A", required: true
      param :team_b, desc: "Comma-separated player names or telegram usernames for team B", required: true

      class << self
        def parse_structured_message(text)
          blocks = text.to_s.split(/\n{2,}/).map(&:strip).reject(&:empty?)
          return [] if blocks.empty?

          parsed = blocks.map { |block| parse_structured_block(block) }
          return nil if parsed.any?(&:nil?)

          parsed
        end

        private

        def parse_structured_block(block)
          attrs = {}

          block.each_line.map(&:strip).reject(&:empty?).each do |line|
            key, value = line.split(":", 2).map { |part| part&.strip }
            return nil if key.blank? || value.blank?

            case key.downcase
            when "date", "дата"
              attrs[:game_date] = value
            when "time", "время"
              attrs[:game_time] = value
            when "hours", "часы"
              attrs[:hours] = value
            when "team a", "команда a"
              attrs[:team_a] = value
            when "team b", "команда b"
              attrs[:team_b] = value
            when "score", "счет", "счёт"
              attrs[:score] = value
            else
              return nil
            end
          end

          return nil unless attrs[:game_date].present? && attrs[:team_a].present? && attrs[:team_b].present? && attrs[:score].present?

          attrs
        end
      end

      def initialize(user)
        @user = user
      end

      def execute(score:, team_a:, team_b:, game_id: nil, game_date: nil, game_time: nil, hours: nil)
        return { error: "User not authenticated." } unless @user

        context = resolve_context(game_id: game_id, game_date: game_date, game_time: game_time)
        return context if context.is_a?(Hash) && context[:error]

        game = context[:game]
        played_at = context[:played_at]

        return { error: "You must be the game creator, a participant, or an admin to record stats for this game." } if game.present? && !authorized?(game)

        parsed_score = Telegram::Flows::StatsScore::ScoreParser.parse(normalized_score_input(score))
        return { error: "Invalid score format. Use for example: 6-2 6-3" } unless parsed_score

        parsed_hours = parse_hours(hours)
        return parsed_hours if parsed_hours.is_a?(Hash)

        team_a_users = resolve_players(team_a, game)
        return team_a_users if team_a_users.is_a?(Hash)

        team_b_users = resolve_players(team_b, game)
        return team_b_users if team_b_users.is_a?(Hash)

        player_ids = (team_a_users + team_b_users).map(&:id)
        return { error: "A player cannot be on both teams." } if player_ids.uniq.size != player_ids.size

        return { error: "Only singles and doubles are supported." } unless supported_team_sizes?(team_a_users, team_b_users)

        mode = team_a_users.size == 1 ? "singles" : "doubles"
        record_matches(
          game: game,
          mode: mode,
          team_a_users: team_a_users,
          team_b_users: team_b_users,
          result: parsed_score[:result],
          played_at: played_at,
          score: parsed_score[:normalized],
          hours: parsed_hours
        )

        {
          success: true,
          message: game.present? ? "Match stats recorded successfully." : "Historical match stats recorded successfully.",
          game_id: game&.id,
          game_date: played_at&.to_date&.iso8601,
          mode: mode,
          score: parsed_score[:normalized],
          hours: parsed_hours,
          recorded_as: format_recorded_result(parsed_score[:result], team_a_users, team_b_users, parsed_score[:normalized]),
          team_a: team_a_users.map { |user| display_name(user) },
          team_b: team_b_users.map { |user| display_name(user) }
        }
      end

      private

      def resolve_context(game_id:, game_date:, game_time:)
        if game_id.present?
          game = Game.find_by(id: game_id)
          return { game: game, played_at: game.date&.in_time_zone || Time.current } if game

          return { error: "Game ##{game_id} was not found." }
        end

        date = parse_game_date(game_date.presence || "today")
        return { error: "Could not understand the game date: #{game_date}" } unless date

        time = parse_game_time(game_time) if game_time.present?
        return { error: "Could not understand the game time: #{game_time}" } if game_time.present? && !time

        return { game: nil, played_at: historical_played_at(date, time) } if @user.admin?

        games = authorized_games.where(date: date).order(:time, :id).to_a
        return { game: games.first, played_at: games.first.date&.in_time_zone || Time.current } if games.one?

        if games.empty?
          return { error: "No authorized game was found for #{date.iso8601}." }
        end

        {
          error: "Multiple authorized games were found for #{date.iso8601}. Please specify game_id.",
          games: games.map { |game| summarize_game(game) }
        }
      end

      def authorized_games
        return Game.all if @user.admin?

        Game.left_joins(:participations)
          .where("games.user_id = :user_id OR participations.user_id = :user_id", user_id: @user.id)
          .distinct
      end

      def authorized?(game)
        @user.admin? || game.user_id == @user.id || game.participations.exists?(user_id: @user.id)
      end

      def parse_game_date(value)
        raw = value.to_s.strip
        return Date.current if raw.casecmp("today").zero?
        return Date.yesterday if raw.casecmp("yesterday").zero?

        Date.parse(raw)
      rescue ArgumentError
        nil
      end

      def parse_game_time(value)
        raw = value.to_s.strip
        match = raw.match(/\A(\d{1,2}):(\d{2})\z/)
        return nil unless match

        hour = match[1].to_i
        minute = match[2].to_i
        return nil unless hour.between?(0, 23) && minute.between?(0, 59)

        { hour: hour, minute: minute }
      end

      def historical_played_at(date, time)
        played_at = date.in_time_zone
        return played_at.end_of_day unless time

        played_at.change(hour: time[:hour], min: time[:minute], sec: 0)
      end

      def resolve_players(raw_team, game)
        names = raw_team.to_s.split(/[,\n;]/).map(&:strip).reject(&:empty?)
        return { error: "Each team must include at least one player." } if names.empty?

        resolved = names.map do |name|
          user =
            if game.present?
              find_player(name, game_players(game))
            elsif @user.admin?
              find_player(name, User.all.to_a)
            end
          return { error: "Could not find player '#{name}'#{game.present? ? ' among the game participants' : ''}." } unless user

          user
        end

        return { error: "A team cannot contain the same player twice." } if resolved.map(&:id).uniq.size != resolved.size

        resolved
      end

      def game_players(game)
        user_ids = [ game.user_id, *game.participations.pluck(:user_id) ].compact.uniq
        User.where(id: user_ids).to_a
      end

      def find_player(name, participants)
        normalized_name = normalize(name)

        exact_match = participants.find do |user|
          [ user.telegram_username, user.name ].compact.map { |value| normalize(value) }.include?(normalized_name)
        end
        return exact_match if exact_match

        partial_matches = participants.select do |user|
          [ user.telegram_username, user.name ].compact.map { |value| normalize(value) }.any? do |value|
            value.include?(normalized_name) || normalized_name.include?(value)
          end
        end

        partial_matches.one? ? partial_matches.first : nil
      end

      def normalize(value)
        value.to_s.delete_prefix("@").strip.downcase
      end

      def normalized_score_input(score)
        score.to_s.tr(":", "-")
      end

      def parse_hours(hours)
        return nil if hours.blank?

        value = hours.to_s.tr(",", ".").strip
        parsed = Float(value)
        return { error: "Hours must be greater than 0." } unless parsed.positive?

        parsed.round(2)
      rescue ArgumentError
        { error: "Invalid hours format. Use for example: 1.5" }
      end

      def record_matches(game:, mode:, team_a_users:, team_b_users:, result:, played_at:, score:, hours:)
        outcome_for_a = result == :a ? "win" : result == :b ? "loss" : "draw"
        outcome_for_b = result == :a ? "loss" : result == :b ? "win" : "draw"

        team_a_users.each do |user|
          PlayerStatistics::UpsertMatchForGameService.new(
            user: user,
            game: game,
            actor: @user,
            mode: mode,
            outcome: outcome_for_a,
            played_at: played_at,
            opponent: (mode == "singles" ? team_b_users.first : nil),
            score: score,
            hours: hours,
            stats: build_stats(team_a_users, team_b_users, user, mode, true)
          ).call
        end

        team_b_users.each do |user|
          PlayerStatistics::UpsertMatchForGameService.new(
            user: user,
            game: game,
            actor: @user,
            mode: mode,
            outcome: outcome_for_b,
            played_at: played_at,
            opponent: (mode == "singles" ? team_a_users.first : nil),
            score: score,
            hours: hours,
            stats: build_stats(team_a_users, team_b_users, user, mode, false)
          ).call
        end
      end

      def build_stats(team_a_users, team_b_users, user, mode, team_a_member)
        my_team = team_a_member ? team_a_users : team_b_users
        opp_team = team_a_member ? team_b_users : team_a_users

        {
          "entered_by" => @user.id,
          "team_a_ids" => team_a_users.map(&:id),
          "team_b_ids" => team_b_users.map(&:id),
          "partner_id" => (mode == "doubles" ? (my_team.map(&:id) - [ user.id ]).first : nil),
          "opponent_ids" => (mode == "doubles" ? opp_team.map(&:id) : opp_team.map(&:id).first(1))
        }.compact
      end

      def supported_team_sizes?(team_a_users, team_b_users)
        [ 1, 2 ].include?(team_a_users.size) && team_a_users.size == team_b_users.size
      end

      def display_name(user)
        return "@#{user.telegram_username}" if user.telegram_username.present?
        return user.name if user.name.present?

        "User ##{user.id}"
      end

      def format_recorded_result(result, team_a_users, team_b_users, score)
        return "Draw #{score}" if result == :draw

        winner =
          case result
          when :a then team_a_users
          when :b then team_b_users
          end

        winner_text = winner ? winner.map { |user| display_name(user) }.join(" / ") : "Match"
        "#{winner_text} won #{score}"
      end

      def summarize_game(game)
        {
          id: game.id,
          date: game.date&.iso8601,
          court_id: game.court_id,
          sport: game.sport
        }
      end
    end
  end
end
