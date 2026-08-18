module Games
  # Win chances for the players of a game, derived from what statistics already
  # hold: the Elo ratings kept on PlayerStatistic and the match history in
  # Match. Nothing here writes — it only reads and estimates.
  class WinChances
    BASE_RATING = PlayerStatistic::BASE_ELO
    # Elo carries as much weight as PRIOR_MATCHES head-to-head meetings: with no
    # history the estimate is pure Elo, and the more the two actually played the
    # more their own record takes over.
    PRIOR_MATCHES = 4.0
    FORM_LIMIT = 5
    MIN_PLAYERS = 2
    MIN_RATED_PLAYERS = 2

    Player = Struct.new(:user, :name, :rating, :rated, :form, keyword_init: true) do
      def rated?
        rated
      end

      def form_wins
        form.count("win")
      end
    end

    Split = Struct.new(:team_a, :team_b, :rating_a, :rating_b, :probability, keyword_init: true)

    Duel = Struct.new(:player, :probability, :wins, :losses, keyword_init: true) do
      def played
        wins + losses
      end
    end

    Result = Struct.new(:mode, :players, :splits, :duels, :viewer, :unrated, keyword_init: true)

    def self.for_game(game, viewer: nil)
      new(game, viewer: viewer).call
    end

    def initialize(game, viewer: nil)
      @game = game
      @viewer = viewer
    end

    def call
      return nil if players.size < MIN_PLAYERS
      return nil if players.count(&:rated?) < MIN_RATED_PLAYERS

      Result.new(
        mode: mode,
        players: players,
        splits: splits,
        duels: duels,
        viewer: viewer_player,
        unrated: players.reject(&:rated?)
      )
    end

    private

    # The block sits under the participants list, so it counts the same people:
    # approved participations. Guests carry no statistics and drop out with the
    # missing user.
    def participants
      @participants ||= begin
        scope = @game.participations
        scope = scope.approved if scope.respond_to?(:approved)
        scope.includes(:user).map(&:user).compact.uniq(&:id)
      end
    end

    # Whoever actually joined decides the mode, not the game's declared size: a
    # four-player game with two players signed up is still a singles matchup.
    def mode
      @mode ||= participants.size >= 4 ? :doubles : :singles
    end

    def players
      @players ||= begin
        statistics = PlayerStatistic.where(user_id: participants.map(&:id)).index_by(&:user_id)
        forms = recent_forms(participants.map(&:id))

        participants.map do |user|
          rating = rating_for(statistics[user.id])

          Player.new(
            user: user,
            name: user.name.presence || user.email,
            rating: (rating || BASE_RATING).to_f,
            rated: rating.present?,
            form: forms[user.id] || []
          )
        end
      end
    end

    def rating_for(statistic)
      return nil if statistic.nil?

      mode == :doubles ? statistic.doubles_rating : statistic.singles_rating
    end

    def recent_forms(user_ids)
      return {} if user_ids.empty?

      Match.where(user_id: user_ids)
        .order(played_at: :desc, id: :desc)
        .pluck(:user_id, :outcome)
        .group_by(&:first)
        .transform_values { |rows| rows.first(FORM_LIMIT).map(&:last) }
    end

    # Teams are only settled once people are on the court, so instead of guessing
    # one line-up we price every way the players can be split. Four players make
    # exactly three pairings; two players make a single duel.
    def splits
      @splits ||=
        case players.size
        when 2 then [ split_for(players.first(1), players.last(1)) ]
        when 4 then pair_splits
        else []
        end
    end

    def pair_splits
      anchor, *rest = players

      rest.map { |partner| split_for([ anchor, partner ], rest - [ partner ]) }
        .sort_by { |split| (split.probability - 0.5).abs }
    end

    def split_for(team_a, team_b)
      rating_a = team_rating(team_a)
      rating_b = team_rating(team_b)

      Split.new(
        team_a: team_a,
        team_b: team_b,
        rating_a: rating_a,
        rating_b: rating_b,
        probability: expected_score(rating_a, rating_b)
      )
    end

    def team_rating(team)
      team.sum(&:rating) / team.size
    end

    def expected_score(rating, opponent_rating)
      1.0 / (1.0 + 10.0**((opponent_rating - rating) / 400.0))
    end

    def duels
      @duels ||= begin
        viewer = viewer_player

        if viewer.nil?
          []
        else
          opponents = players - [ viewer ]
          history = head_to_head(viewer.user.id, opponents.map { |player| player.user.id })

          opponents.map do |opponent|
            wins, losses = history[opponent.user.id] || [ 0, 0 ]

            Duel.new(
              player: opponent,
              probability: blend(expected_score(viewer.rating, opponent.rating), wins, losses),
              wins: wins,
              losses: losses
            )
          end.sort_by { |duel| -duel.probability }
        end
      end
    end

    def viewer_player
      return nil if @viewer.nil?

      @viewer_player ||= players.find { |player| player.user.id == @viewer.id }
    end

    def blend(elo_probability, wins, losses)
      played = wins + losses
      return elo_probability if played.zero?

      ((elo_probability * PRIOR_MATCHES) + wins) / (PRIOR_MATCHES + played)
    end

    def head_to_head(user_id, opponent_ids)
      return {} if opponent_ids.empty?

      counts = {}

      Match.where(user_id: user_id).where.not(outcome: "draw").find_each do |match|
        faced = opponents_in(match, user_id) & opponent_ids
        next if faced.empty?

        index = match.outcome == "win" ? 0 : 1
        faced.each do |id|
          counts[id] ||= [ 0, 0 ]
          counts[id][index] += 1
        end
      end

      counts
    end

    # A match row belongs to one player, so the other side is either the team the
    # player is not on (doubles) or the recorded opponent (singles).
    def opponents_in(match, user_id)
      stats = match.stats.to_h
      team_a = normalize_ids(stats["team_a_ids"])
      team_b = normalize_ids(stats["team_b_ids"])

      return team_b if team_a.include?(user_id)
      return team_a if team_b.include?(user_id)

      (normalize_ids(stats["opponent_ids"]) + [ match.opponent_id ]).compact.uniq
    end

    def normalize_ids(value)
      Array(value).map(&:to_i).reject(&:zero?)
    end
  end
end
