require "test_helper"

class Scoreboard::OneVsTwoStateTest < ActiveSupport::TestCase
  # Одиночка по кругу: гейм 1 — A, 2 — B, 3 — C, 4 — снова A.
  test "the single player rotates and scores only the games won alone" do
    board = Scoreboard::OneVsTwoState.new(%w[w l w w l w])

    assert_equal [ 2, 0, 2 ], board.solo_wins
    assert_equal [ 2, 2, 2 ], board.solo_played
    assert_equal 0, board.solo_index, "седьмой гейм снова играет A"
    assert_equal [ 0, 2 ], board.leaders
    assert_equal "2-2-0", board.score_string
  end

  test "a single leader wins and the others lose" do
    board = Scoreboard::OneVsTwoState.new(%w[l w l])

    assert_equal %w[loss win loss], (0..2).map { |index| board.outcome(index) }
    assert_equal [ 1, 0, 2 ], board.ranking
  end

  test "a shared first place is a draw for the leaders, all equal is a draw for everyone" do
    shared = Scoreboard::OneVsTwoState.new(%w[w l w])
    assert_equal %w[draw loss draw], (0..2).map { |index| shared.outcome(index) }

    even = Scoreboard::OneVsTwoState.new(%w[l l l])
    assert_equal %w[draw draw draw], (0..2).map { |index| even.outcome(index) }
  end

  test "a plus for any player counts for them and hands the turn to the next one" do
    board = Scoreboard::OneVsTwoState.new(%w[w:1 l w:1])

    assert_equal [ 0, 2, 0 ], board.solo_wins
    assert_equal [ 0, 2, 1 ], board.solo_played
    assert_equal 2, board.solo_index
    assert_equal [ 1, nil, 1 ], board.winners
  end
end
