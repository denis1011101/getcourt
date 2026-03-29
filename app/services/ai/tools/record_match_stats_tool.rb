module Ai
  module Tools
    class RecordMatchStatsTool < RubyLLM::Tool
      description "Record match score for a game. The current user must be the game creator or a participant."
      param :game_id, desc: "ID of the game to record stats for", required: false
      param :game_date, desc: "Game date, for example 'today' or '2026-03-24'", required: false
      param :score, desc: 'Match score, for example "6-2 6-3"', required: true
      param :team_a, desc: "Comma-separated player names or telegram usernames for team A", required: true
      param :team_b, desc: "Comma-separated player names or telegram usernames for team B", required: true

      def initialize(user)
        @user = user
      end

      def execute(score:, team_a:, team_b:, game_id: nil, game_date: nil)
        return { error: "User not authenticated." } unless @user

        game = find_game(game_id: game_id, game_date: game_date)
        return game if game.is_a?(Hash)

        return { error: "You must be the game creator or a participant to record stats for this game." } unless authorized?(game)

        parsed_score = Telegram::Flows::StatsScore::ScoreParser.parse(score.to_s)
        return { error: "Invalid score format. Use for example: 6-2 6-3" } unless parsed_score

        team_a_users = resolve_players(team_a, game)
        return team_a_users if team_a_users.is_a?(Hash)

        team_b_users = resolve_players(team_b, game)
        return team_b_users if team_b_users.is_a?(Hash)

        player_ids = (team_a_users + team_b_users).map(&:id)
        return { error: "A player cannot be on both teams." } if player_ids.uniq.size != player_ids.size

        return { error: "Only singles and doubles are supported." } unless supported_team_sizes?(team_a_users, team_b_users)

        mode = team_a_users.size == 1 ? "singles" : "doubles"

        Telegram::Flows::StatsScore::MatchUpserter.call(
          game: game,
          actor: @user,
          mode: mode,
          team_a_ids: team_a_users.map(&:id),
          team_b_ids: team_b_users.map(&:id),
          result: parsed_score[:result],
          played_at: game.date&.in_time_zone || Time.current,
          score: parsed_score[:normalized]
        )

        {
          success: true,
          message: "Match stats recorded successfully.",
          game_id: game.id,
          game_date: game.date&.iso8601,
          mode: mode,
          score: parsed_score[:normalized],
          recorded_as: format_recorded_result(parsed_score[:result], team_a_users, team_b_users, parsed_score[:normalized]),
          team_a: team_a_users.map { |user| display_name(user) },
          team_b: team_b_users.map { |user| display_name(user) }
        }
      end

      private

      def find_game(game_id:, game_date:)
        if game_id.present?
          game = Game.find_by(id: game_id)
          return game if game

          return { error: "Game ##{game_id} was not found." }
        end

        return { error: "Please specify the game_id or the game_date." } if game_date.blank?

        date = parse_game_date(game_date)
        return { error: "Could not understand the game date: #{game_date}" } unless date

        games = authorized_games.where(date: date).order(:time, :id).to_a
        return games.first if games.one?

        if games.empty?
          return { error: "No authorized game was found for #{date.iso8601}." }
        end

        {
          error: "Multiple authorized games were found for #{date.iso8601}. Please specify game_id.",
          games: games.map { |game| summarize_game(game) }
        }
      end

      def authorized_games
        Game.left_joins(:participations)
          .where("games.user_id = :user_id OR participations.user_id = :user_id", user_id: @user.id)
          .distinct
      end

      def authorized?(game)
        game.user_id == @user.id || game.participations.exists?(user_id: @user.id)
      end

      def parse_game_date(value)
        raw = value.to_s.strip
        return Date.current if raw.casecmp("today").zero?
        return Date.yesterday if raw.casecmp("yesterday").zero?

        Date.parse(raw)
      rescue ArgumentError
        nil
      end

      def resolve_players(raw_team, game)
        names = raw_team.to_s.split(/[,\n;]/).map(&:strip).reject(&:empty?)
        return { error: "Each team must include at least one player." } if names.empty?

        participants = game_players(game)
        resolved = names.map do |name|
          user = find_player(name, participants)
          return { error: "Could not find player '#{name}' among the game participants." } unless user

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
