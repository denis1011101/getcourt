require "test_helper"

class Scoreboard::TennisStateTest < ActiveSupport::TestCase
  POINTS = { "mode" => "points", "sets_to_win" => 2, "tiebreak" => true, "golden_point" => false }.freeze

  def state(actions, **settings)
    Scoreboard::TennisState.new(POINTS.merge(settings.stringify_keys), actions)
  end

  # Гейм «под ноль»: четыре очка подряд.
  def game(side) = [ side ] * 4

  test "counts points as 15, 30, 40" do
    board = state(%w[a a b])

    assert_equal "30", board.point_label("a")
    assert_equal "15", board.point_label("b")
  end

  test "deuce and advantage" do
    board = state(%w[a a a b b b a])

    assert_equal "AD", board.point_label("a")
    assert_equal "40", board.point_label("b")
    assert_equal 0, board.games["a"], "преимущество ещё не гейм"

    board = state(%w[a a a b b b a b])
    assert_equal [ "40", "40" ], [ board.point_label("a"), board.point_label("b") ]
  end

  test "golden point decides the game at 40-40" do
    board = state(%w[a a a b b b b], golden_point: true)

    assert_equal 1, board.games["b"]
  end

  test "a set is won at 6 games with a two-game lead" do
    board = state(game("a") * 6)

    assert_equal "6-0", board.score_string
    assert_equal 1, board.sets_won("a")
  end

  test "plays a tiebreak at 6-6 and records the loser's points" do
    actions = (game("a") + game("b")) * 6 + (%w[a b] * 5) + %w[a a]
    board = state(actions)

    assert_equal "7-6(5)", board.score_string
  end

  test "without a tiebreak the set goes on until a two-game lead" do
    board = state((game("a") + game("b")) * 6 + game("a"), tiebreak: false)

    assert_not board.tiebreak?
    assert_equal({ "a" => 7, "b" => 6 }, board.games)
  end

  test "the match ends when a side reaches the sets to win and ignores later points" do
    board = state(game("a") * 12 + game("b"))

    assert board.finished?
    assert_equal :a, board.result
    assert_equal "6-0 6-0", board.score_string
  end

  test "games mode counts games directly and treats the 13th game as the tiebreak" do
    board = Scoreboard::TennisState.new({ "mode" => "games", "sets_to_win" => 1 }, %w[a b] * 6 + %w[b])

    assert board.finished?
    assert_equal "6-7", board.score_string
    assert_equal :b, board.result
  end

  test "an unfinished match keeps the current set in the score and counts it" do
    board = state(game("a") * 6 + game("b") * 2)

    assert_equal "6-0 0-2", board.score_string
    assert_equal :draw, board.result, "сет на сет — ничья"
  end

  GAMES = { "mode" => "games", "sets_to_win" => 2 }.freeze

  test "a set closed by hand keeps the games when the side leads" do
    board = Scoreboard::TennisState.new(GAMES, %w[a a a b s:a])

    assert_equal "3-1", board.score_string
    assert_equal 1, board.sets_won("a")
  end

  # Сет отдали стороне, которая не вела: перевес в один гейм, а не выдуманные 6:0.
  test "a set closed by hand for the trailing side gets a one-game lead" do
    board = Scoreboard::TennisState.new(GAMES, %w[a a s:b])

    assert_equal "2-3", board.score_string
  end

  test "the last set won by a side is found with all its actions" do
    actions = %w[a] * 6 + %w[b a b s:b]
    board = Scoreboard::TennisState.new(GAMES, actions)

    assert_equal (0..5), board.last_set_range("a")
    assert_equal (6..9), board.last_set_range("b")
  end

  # Смена режима посреди матча не должна терять сыгранное.
  test "switching from full score to games keeps sets and games, drops the points" do
    actions = game("a") * 6 + game("b") * 2 + %w[a a]
    board = state(actions)
    rebuilt = Scoreboard::TennisState.new(POINTS.merge("mode" => "games"), board.actions_for("games"))

    assert_equal "6-0 0-2", rebuilt.score_string
  end

  test "switching from games to full score keeps a hand-closed set and a tiebreak set" do
    games = Scoreboard::TennisState.new(GAMES, %w[a b] * 6 + %w[a] + %w[a b s:b])
    rebuilt = Scoreboard::TennisState.new(POINTS, games.actions_for("points"))

    assert_equal "7-6(0) 1-2", rebuilt.score_string
  end

  test "a tiebreak score is attached to a 7-6 set closed in games mode" do
    actions = %w[a b] * 6 + %w[a tb:5] + %w[b]
    board = Scoreboard::TennisState.new(GAMES, actions)

    assert_equal "7-6(5) 0-1", board.score_string
    assert_equal 0, board.tiebreak_editable_set, "записанный руками тай-брейк можно поправить"
    assert_equal({ "a" => 7, "b" => 5 }, board.tiebreak_points(board.sets.first))
    assert_equal (0..13), board.last_set_range("a"), "«− сет» уносит и счёт тай-брейка"
  end

  test "a 7-6 set without a tiebreak score is offered for filling in" do
    board = Scoreboard::TennisState.new(GAMES, %w[a b] * 6 + %w[b])

    assert_equal 0, board.tiebreak_editable_set
  end

  test "the tiebreak score survives switching to full score" do
    games = Scoreboard::TennisState.new(GAMES, %w[a b] * 6 + %w[a tb:8])
    rebuilt = Scoreboard::TennisState.new(POINTS, games.actions_for("points"))

    assert_equal "7-6(8)", rebuilt.score_string
  end
end
