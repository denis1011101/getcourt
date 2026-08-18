require "test_helper"

module Games
  class WinChancesTest < ActiveSupport::TestCase
    test "stays hidden until two players carry a rating" do
      rated = build_player(singles_rating: 1500.0)
      unrated = build_player

      game = build_game([ rated, unrated ])

      assert_nil Games::WinChances.for_game(game, viewer: rated)
    end

    test "counts a player without a rating as the base one" do
      rated = build_player(singles_rating: 1500.0)
      other = build_player(singles_rating: 1500.0)
      unrated = build_player

      game = build_game([ rated, other, unrated ])
      chances = Games::WinChances.for_game(game, viewer: rated)

      assert_equal [ unrated ], chances.unrated.map(&:user)
      assert_equal PlayerStatistic::BASE_ELO, chances.players.find { |p| p.user == unrated }.rating
    end

    test "puts the most even pairing first" do
      strongest = build_player(doubles_rating: 1600.0)
      middle_one = build_player(doubles_rating: 1500.0)
      middle_two = build_player(doubles_rating: 1500.0)
      weakest = build_player(doubles_rating: 1400.0)

      game = build_game([ strongest, middle_one, middle_two, weakest ])
      chances = Games::WinChances.for_game(game, viewer: strongest)

      assert_equal :doubles, chances.mode
      assert_equal 3, chances.splits.size

      evenest = chances.splits.first
      assert_equal [ strongest, weakest ], evenest.team_a.map(&:user)
      assert_equal [ middle_one, middle_two ], evenest.team_b.map(&:user)
      assert_in_delta 0.5, evenest.probability, 0.0001
      assert chances.splits.last.probability > 0.6
    end

    test "leans the duel towards the head-to-head record" do
      viewer = build_player(singles_rating: 1500.0)
      rival = build_player(singles_rating: 1500.0)

      3.times { |index| record_singles(viewer, rival, "win", played_at: (index + 1).days.ago) }

      game = build_game([ viewer, rival ])
      duel = Games::WinChances.for_game(game, viewer: viewer).duels.sole

      assert_equal rival, duel.player.user
      assert_equal [ 3, 0 ], [ duel.wins, duel.losses ]
      # Elo alone says 50%, three wins pull it up: (0.5 * 4 + 3) / (4 + 3).
      assert_in_delta 0.714, duel.probability, 0.001
    end

    test "reads the head-to-head record out of doubles team ids" do
      viewer = build_player(doubles_rating: 1500.0)
      partner = build_player(doubles_rating: 1500.0)
      rival = build_player(doubles_rating: 1500.0)
      rival_partner = build_player(doubles_rating: 1500.0)

      Match.create!(
        user: viewer,
        mode: "doubles",
        outcome: "loss",
        played_at: 1.day.ago,
        stats: {
          "team_a_ids" => [ viewer.id, partner.id ],
          "team_b_ids" => [ rival.id, rival_partner.id ]
        }
      )

      game = build_game([ viewer, partner, rival, rival_partner ])
      duels = Games::WinChances.for_game(game, viewer: viewer).duels.index_by { |duel| duel.player.user }

      assert_equal [ 0, 1 ], [ duels[rival].wins, duels[rival].losses ]
      assert_equal [ 0, 1 ], [ duels[rival_partner].wins, duels[rival_partner].losses ]
      assert_equal [ 0, 0 ], [ duels[partner].wins, duels[partner].losses ]
    end

    test "keeps only the latest outcomes in the form" do
      player = build_player(singles_rating: 1500.0)
      rival = build_player(singles_rating: 1500.0)

      record_singles(player, rival, "loss", played_at: 6.days.ago)
      %w[win loss win win draw].each_with_index do |outcome, index|
        record_singles(player, rival, outcome, played_at: (5 - index).days.ago)
      end

      game = build_game([ player, rival ])
      form = Games::WinChances.for_game(game, viewer: player).players.find { |p| p.user == player }.form

      assert_equal %w[draw win win loss win], form
    end

    test "skips the duels when the viewer is not playing" do
      one = build_player(singles_rating: 1500.0)
      two = build_player(singles_rating: 1500.0)
      onlooker = build_player(singles_rating: 1500.0)

      game = build_game([ one, two ])
      chances = Games::WinChances.for_game(game, viewer: onlooker)

      assert_empty chances.duels
      assert_equal 1, chances.splits.size
    end

    private

    def build_player(**ratings)
      user = User.create!(email: "chances-#{SecureRandom.hex(4)}@example.com", name: "Player #{SecureRandom.hex(2)}")
      user.create_player_statistic!(**ratings) if ratings.any?
      user
    end

    def build_game(users)
      game = Game.create!(court: courts(:one), user: users.first, date: Date.yesterday, time: "10:00")
      users.each { |user| Participation.create!(game: game, user: user, status: "approved") }
      game
    end

    def record_singles(user, opponent, outcome, played_at:)
      Match.create!(user: user, opponent: opponent, mode: "singles", outcome: outcome, played_at: played_at)
    end
  end
end
