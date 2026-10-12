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

class GameScoreboardTrioTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @second = User.create!(email: "trio-second@example.com", name: "Second")
    @third = User.create!(email: "trio-third@example.com", name: "Third")
    @game = Game.create!(court: courts(:one), user: @owner, date: Date.yesterday, time: "10:00")
    @trio = [ "u:#{@owner.id}", "u:#{@second.id}", "u:#{@third.id}" ]
  end

  def start(kind, trio: @trio, settings: {})
    GameScoreboard.start(game: @game, user: @owner, settings: { "kind" => kind, "mode" => "games", "sets_to_win" => 1 }.merge(settings),
                         team_a: {}, team_b: {}, trio: trio).tap(&:save!)
  end

  test "2 against 1 needs three different players" do
    board = GameScoreboard.start(game: @game, user: @owner, settings: { "kind" => "one_vs_two" }, team_a: {}, team_b: {}, trio: @trio.first(2))

    assert_not board.valid?
    assert board.errors.of_kind?(:base, :trio_needs_three)
  end

  test "2 against 1: every player has a plus and a minus, the pair its own" do
    board = start("one_vs_two")
    board.score!("0")
    board.score!("pair")
    board.score!("2")
    board.score!("0")
    board.score!("bogus")
    board.unscore!("0")

    assert_equal %w[w:0 l w:2], board.reload.actions
    assert_equal [ 1, 0, 1 ], board.state.solo_wins
    assert_equal 0, board.state.solo_index, "после гейма C одним снова становится A"

    board.unscore!("pair")
    assert_equal %w[w:0 w:2], board.reload.actions
    board.unscore!("1")
    assert_equal %w[w:0 w:2], board.reload.actions, "у B нет выигранных геймов — снимать нечего"
  end

  test "finishing 2 against 1 records one match for three: the leader wins, the others lose, singles Elo moves" do
    wins_before = @owner.player_statistic&.singles_wins.to_i
    board = start("one_vs_two")
    %w[0 1 pair 0].each { |side| board.score!(side) } # A: 2 из 2, B: 1 из 1, C: 0 из 1

    assert board.finish!(@owner)

    matches = Match.where(game: @game, mode: "one_vs_two").index_by(&:user_id)
    assert_equal({ @owner.id => "win", @second.id => "loss", @third.id => "loss" }, matches.transform_values(&:outcome))
    assert_equal [ "2-1-0" ], matches.values.map(&:score).uniq
    assert_equal [ @owner.id ], matches[@owner.id].stats["team_a_ids"]
    assert_equal 1, matches.values.map { |match| match.stats["match_group_id"] }.uniq.size

    ratings = PlayerStatistic.where(user_id: [ @owner.id, @second.id ]).pluck(:user_id, :singles_rating).to_h
    assert_operator ratings[@owner.id], :>, PlayerStatistic::BASE_ELO
    assert_operator ratings[@second.id], :<, PlayerStatistic::BASE_ELO
    assert_equal wins_before + 1, @owner.reload.player_statistic.singles_wins
  end

  test "a three-player series moves to the next pair on finish and stops after the third" do
    board = start("round_robin")
    assert_equal [ @owner.id ], board.team_a["user_ids"]
    assert_equal [ @second.id ], board.team_b["user_ids"]

    board.score!("a")
    board.finish!(@owner)
    second = board.next_in_series
    assert_equal [ @owner.id, @third.id ], [ second.team_a["user_ids"], second.team_b["user_ids"] ].flatten
    assert_equal 1, second.series_index

    second.finish!(@owner)
    third = second.next_in_series
    assert_equal [ @second.id, @third.id ], [ third.team_a["user_ids"], third.team_b["user_ids"] ].flatten

    third.finish!(@owner)
    assert_nil third.next_in_series
    assert_equal 3, third.series_scoreboards.size
    assert_equal [ @owner.id, @second.id ], Match.where(game: @game, mode: "singles").order(:user_id).pluck(:user_id),
                 "в статистику ушёл только сыгранный матч A–B, пустые пары пропущены"
  end

  test "a series with two guests is refused — their match would have nowhere to go" do
    board = GameScoreboard.start(game: @game, user: @owner, settings: { "kind" => "round_robin" }, team_a: {}, team_b: {},
                                 trio: [ "u:#{@owner.id}", "g:Guest 1", "g:Guest 2" ])

    assert_not board.valid?
    assert board.errors.of_kind?(:base, :trio_one_guest)
  end
end
