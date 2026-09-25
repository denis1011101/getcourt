require "test_helper"

class GameScoreboardTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @rival = User.create!(email: "scoreboard-model-rival@example.com")
    @game = Game.create!(court: courts(:one), user: @owner, date: Date.yesterday, time: "10:00")
    @scoreboard = @game.scoreboards.create!(
      user: @owner, settings: { "mode" => "games", "sets_to_win" => 2 },
      team_a: { "user_ids" => [ @owner.id ] }, team_b: { "user_ids" => [ @rival.id ] }
    )
  end

  # Регрессия из ревью: позиция токена считалась до замка. Если другой
  # телефон успел сбросить тай-брейк, замена по старому индексу затирала
  # следующий гейм.
  test "a tiebreak change finds its set under the lock, after a reset from another phone" do
    @scoreboard.update!(actions: %w[a b] * 6 + %w[a tb:4 b])
    other_phone = GameScoreboard.find(@scoreboard.id)

    other_phone.reset_tiebreak!
    assert_nil @scoreboard.record_tiebreak!(7, 5)

    assert_equal "7-6(5) 0-1", @scoreboard.reload.state.score_string
  end

  # Регрессия из ревью: после смены режима сет 6:0 заморожен, и «−» снимал
  # гейм (5:0), но сет оставался закрытым, а матч — оконченным.
  test "minus reopens a frozen set when it takes back one of its games" do
    @scoreboard.update!(settings: { "mode" => "games", "sets_to_win" => 1 }, actions: %w[a] * 6)
    assert @scoreboard.state.finished?

    @scoreboard.update_setup!(settings: { "mode" => "points", "sets_to_win" => 1, "tiebreak" => true, "golden_point" => false },
                              team_a: @scoreboard.team_a, team_b: @scoreboard.team_b)
    @scoreboard.unscore!("a")

    board = @scoreboard.reload.state
    assert_not board.finished?
    assert_empty board.sets
    assert_equal({ "a" => 5, "b" => 0 }, board.games)

    @scoreboard.score!("a") until @scoreboard.reload.state.finished?
    assert_equal "6-0", @scoreboard.state.score_string, "гейм доигран по очкам — сет снова закрылся сам"
  end

  test "a frozen 7-6 set drops its tiebreak score together with the reopened set" do
    @scoreboard.update!(actions: %w[a b] * 6 + %w[a tb:5 b])
    @scoreboard.update_setup!(settings: { "mode" => "points", "sets_to_win" => 2, "tiebreak" => true, "golden_point" => false },
                              team_a: @scoreboard.team_a, team_b: @scoreboard.team_b)
    assert_equal "7-6(5) 0-1", @scoreboard.reload.state.score_string

    @scoreboard.unscore!("a")

    board = @scoreboard.reload.state
    assert_empty board.sets
    # Сет открыт: 6:6 из первого сета плюс гейм B, сыгранный уже после него.
    assert_equal({ "a" => 6, "b" => 7 }, board.games)
    assert_nil board.tiebreak_editable_set, "счёт тай-брейка ушёл вместе с закрытием сета"
  end

  # Сет, закрытый кнопкой, — решение человека: «−» по гейму его не открывает.
  test "a set closed by hand stays closed when a game is taken back" do
    @scoreboard.update!(actions: %w[a a a b s:a])

    @scoreboard.unscore!("a")

    assert_equal "2-1", @scoreboard.reload.state.score_string
  end
end
