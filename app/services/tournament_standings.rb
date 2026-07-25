class TournamentStandings
  class << self
    def compute(tournament)
      rows = {}
      matches = tournament.tournament_matches.order(:played_at, :id)
      all_user_ids = matches.flat_map { |m| [ m.player_a_id, m.player_b_id, m.player_a2_id, m.player_b2_id ] }.compact.uniq
      users_by_id = User.where(id: all_user_ids).index_by(&:id)

      matches.each do |m|
        parsed = parse_score(m.score)
        next unless parsed

        team_a_ids = [ m.player_a_id, m.player_a2_id ].compact
        team_b_ids = [ m.player_b_id, m.player_b2_id ].compact

        team_a_ids.each do |uid|
          user = users_by_id[uid]
          next unless user
          row = (rows[uid] ||= empty_row(user))
          row[:sets_won] += parsed[:sets_a]
          row[:sets_lost] += parsed[:sets_b]
          row[:games_won] += parsed[:games_a]
          row[:games_lost] += parsed[:games_b]
        end

        team_b_ids.each do |uid|
          user = users_by_id[uid]
          next unless user
          row = (rows[uid] ||= empty_row(user))
          row[:sets_won] += parsed[:sets_b]
          row[:sets_lost] += parsed[:sets_a]
          row[:games_won] += parsed[:games_b]
          row[:games_lost] += parsed[:games_a]
        end

        case m.result
        when "player_a"
          team_a_ids.each { |uid| rows[uid][:wins] += 1 if rows[uid] }
          team_b_ids.each { |uid| rows[uid][:losses] += 1 if rows[uid] }
        when "player_b"
          team_b_ids.each { |uid| rows[uid][:wins] += 1 if rows[uid] }
          team_a_ids.each { |uid| rows[uid][:losses] += 1 if rows[uid] }
        end
      end

      rows.values.sort_by do |r|
        [ -r[:wins], -ratio(r[:sets_won], r[:sets_lost]), -ratio(r[:games_won], r[:games_lost]), r[:user].id ]
      end
    end

    def parse_score(score)
      tokens = score.to_s.strip.split(/\s+/).reject(&:blank?)
      return nil if tokens.empty?

      games_a = 0
      games_b = 0
      sets_a = 0
      sets_b = 0

      tokens.each do |set_token|
        # Sets look like "6-4"; a tiebreak set carries the loser's points: "7-6(5)".
        m = set_token.match(/\A(\d{1,2})[-:](\d{1,2})(?:\(\d{1,2}\))?\z/)
        return nil unless m

        a = m[1].to_i
        b = m[2].to_i
        games_a += a
        games_b += b
        sets_a += 1 if a > b
        sets_b += 1 if b > a
      end

      { sets_a: sets_a, sets_b: sets_b, games_a: games_a, games_b: games_b }
    end

    private

    def empty_row(user)
      { user: user, wins: 0, losses: 0, sets_won: 0, sets_lost: 0, games_won: 0, games_lost: 0, points: 0 }
    end

    def ratio(won, lost)
      return won.to_f if lost.to_i <= 0
      won.to_f / lost.to_f
    end
  end
end
