require "test_helper"

require "turbo/broadcastable/test_helper"

class GameScoreboardsControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper
  setup do
    post session_url, params: { email: "scoreboard-owner@example.com" }
    @owner = User.find_by!(email: "scoreboard-owner@example.com")
    @rival = User.create!(email: "scoreboard-rival@example.com", name: "Rival")
    @game = Game.create!(court: courts(:one), user: @owner, date: Date.yesterday, time: "10:00")
    @game.participations.create!(user: @rival)
  end

  def start_match(mode: "points", sets: 1)
    post game_scoreboard_url(@game), params: {
      team_a: [ "u:#{@owner.id}", "" ],
      team_b: [ "u:#{@rival.id}", "" ],
      settings: { mode: mode, sets_to_win: sets, tiebreak: "1", golden_point: "0" }
    }
    @game.scoreboards.live.first
  end

  def live_id
    @game.scoreboards.live.pick(:id)
  end

  def tap(side, times = 1)
    times.times { post score_game_scoreboard_url(@game), params: { scoreboard_id: live_id, side: side }, as: :turbo_stream }
  end

  test "an organiser sets up the sides and starts a match" do
    get game_scoreboard_url(@game)
    assert_response :success
    assert_select "select[name='team_a[]']", 2
    # Ревью: умолчание собиралось из пустых настроек и выходило «до 1 сета».
    assert_select "input[name='settings[sets_to_win]'][value='2'][checked]"

    scoreboard = start_match

    assert scoreboard
    assert_redirected_to game_scoreboard_url(@game)
    assert_equal [ @owner.id ], scoreboard.team_a["user_ids"]
  end

  test "points arrive as a turbo stream, and minus takes the side's last point back" do
    scoreboard = start_match
    tap("a", 2)
    tap("b")

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal %w[a a b], scoreboard.reload.actions

    post unscore_game_scoreboard_url(@game), params: { scoreboard_id: live_id, side: "a" }, as: :turbo_stream
    assert_equal %w[a b], scoreboard.reload.actions
  end

  # Второй телефон и зрители узнают о счёте только из рассылки.
  test "every point is broadcast to the watchers of the game" do
    start_match

    assert_turbo_stream_broadcasts [ @game, :scoreboard ], count: 1 do
      tap("a")
    end
  end

  test "the game page leads to a live match" do
    start_match
    tap("a", 4)

    get game_url(@game)

    assert_select "a[href='#{game_scoreboard_path(@game)}']", text: /Match in progress/
  end

  # В режиме геймов «− сет» убирает сет целиком — вместе с геймами соперника.
  test "games mode closes a set by hand and minus set takes the whole set back" do
    scoreboard = start_match(mode: "games", sets: 2)
    tap("a", 6)
    tap("b", 2)
    post score_game_scoreboard_url(@game), params: { scoreboard_id: live_id, side: "b", unit: "set" }, as: :turbo_stream

    assert_equal "6-0 0-2", scoreboard.reload.state.score_string

    post unscore_game_scoreboard_url(@game), params: { scoreboard_id: live_id, side: "a", unit: "set" }, as: :turbo_stream
    assert_equal "0-2", scoreboard.reload.state.score_string

    get game_scoreboard_url(@game)
    assert_select "input[name=unit][value=set]", 4, "по «+ сет» и «− сет» у каждой стороны"
  end

  # Ошиблись при старте — настройки меняются посреди матча, счёт остаётся.
  test "settings and sides can be changed mid-match without losing the score" do
    scoreboard = start_match(mode: "games", sets: 2)
    tap("a", 6)
    tap("b", 2)

    get edit_game_scoreboard_url(@game, scoreboard_id: live_id)
    assert_response :success
    assert_select "input[name='settings[mode]'][value=games][checked]"
    assert_select "select[name='team_a[]'] option[selected][value='u:#{@owner.id}']"

    patch game_scoreboard_url(@game), params: {
      scoreboard_id: live_id,
      team_a: [ "u:#{@rival.id}" ], team_b: [ "u:#{@owner.id}" ],
      settings: { mode: "points", sets_to_win: 3, tiebreak: "1", golden_point: "0" }
    }

    assert_redirected_to game_scoreboard_url(@game)
    scoreboard.reload
    assert_equal "points", scoreboard.settings["mode"]
    assert_equal [ @rival.id ], scoreboard.team_a["user_ids"]
    assert_equal "6-0 0-2", scoreboard.state.score_string
  end

  # В режиме геймов очков тай-брейка нет — их дописывают после 7:6.
  test "a tiebreak score is added to a 7-6 set and goes to the statistics" do
    scoreboard = start_match(mode: "games", sets: 1)
    6.times { tap("a"); tap("b") }
    tap("a")

    assert_select "input[name=a]", 1
    post tiebreak_game_scoreboard_url(@game), params: { scoreboard_id: live_id, a: 7, b: 9 }, as: :turbo_stream
    assert_nil scoreboard.reload.state.sets.first["tb"], "7:9 не тай-брейк победителя сета"
    assert_select "[role=alert]", /won the set/

    post tiebreak_game_scoreboard_url(@game), params: { scoreboard_id: live_id, a: 7, b: 6 }, as: :turbo_stream
    assert_select "[role=alert]", /two-point lead/

    post tiebreak_game_scoreboard_url(@game), params: { scoreboard_id: live_id, a: 7, b: 5 }, as: :turbo_stream
    assert_equal "7-6(5)", scoreboard.reload.state.score_string
    assert_select "input[name=a][value='7']", 1, "сохранённый счёт виден и правится"

    post tiebreak_game_scoreboard_url(@game), params: { scoreboard_id: live_id, a: 10, b: 8 }, as: :turbo_stream
    assert_equal "7-6(8)", scoreboard.reload.state.score_string

    post reset_tiebreak_game_scoreboard_url(@game), params: { scoreboard_id: live_id }, as: :turbo_stream
    assert_equal "7-6", scoreboard.reload.state.score_string

    post tiebreak_game_scoreboard_url(@game), params: { scoreboard_id: live_id, a: 7, b: 5 }, as: :turbo_stream

    post finish_game_scoreboard_url(@game), params: { scoreboard_id: live_id }
    assert_equal "7-6(5)", Match.find_by!(game: @game, user: @owner).score
  end

  # Матч выигран — «+» гаснет, а экран говорит, что делать дальше.
  test "a won match disables plus and offers to save the score" do
    start_match(mode: "games", sets: 1)
    tap("a", 6)

    assert_select "[role=status]", /Match over/
    assert_select "form[action='#{score_game_scoreboard_path(@game)}'] button[disabled]", 4, "«+ гейм» и «+ сет» у обеих сторон"
    assert_select "form[action='#{unscore_game_scoreboard_path(@game)}'] button:not([disabled])", 4
  end

  # Регрессия из ревью: вкладка с первым матчем не должна менять или
  # завершать второй, начатый после.
  test "a stale page cannot touch the next match" do
    first = start_match(mode: "games", sets: 1)
    tap("a", 6)
    post finish_game_scoreboard_url(@game), params: { scoreboard_id: first.id }
    second = start_match(mode: "games", sets: 1)

    post score_game_scoreboard_url(@game), params: { scoreboard_id: first.id, side: "a" }, as: :turbo_stream
    post finish_game_scoreboard_url(@game), params: { scoreboard_id: first.id }

    assert_redirected_to game_scoreboard_url(@game)
    assert second.reload.live?
    assert_empty second.actions
  end

  # Регрессия из ревью: у второго телефона после чужого «−» должны ожить
  # кнопки — поэтому рассылаем обновление страницы, а не готовое табло.
  test "every change asks all open scoreboards to refresh" do
    start_match(mode: "games", sets: 1)
    tap("a", 6)

    streams = capture_turbo_stream_broadcasts [ @game, :scoreboard ] do
      post unscore_game_scoreboard_url(@game), params: { scoreboard_id: live_id, side: "a" }, as: :turbo_stream
    end

    assert_equal [ "refresh" ], streams.map { |stream| stream["action"] }
  end

  test "finishing writes the score to the game statistics" do
    start_match(mode: "games", sets: 1)
    tap("a", 6)

    post finish_game_scoreboard_url(@game), params: { scoreboard_id: live_id }

    assert_redirected_to game_url(@game)
    match = Match.find_by!(game: @game, user: @owner)
    assert_equal "6-0", match.score
    assert_equal "win", match.outcome
    assert_equal "loss", Match.find_by!(game: @game, user: @rival).outcome
    assert_empty @game.scoreboards.live
  end

  test "a player from outside the game is dropped from the sides" do
    stranger = User.create!(email: "scoreboard-stranger@example.com")

    post game_scoreboard_url(@game), params: {
      team_a: [ "u:#{@owner.id}" ], team_b: [ "u:#{stranger.id}" ], settings: { mode: "points" }
    }

    assert_response :unprocessable_entity
    assert_empty @game.scoreboards
  end

  test "only people of the game can keep the score, but anyone can watch" do
    start_match
    delete sign_out_url
    post session_url, params: { email: "scoreboard-outsider@example.com" }

    get game_scoreboard_url(@game)
    assert_response :success
    assert_select "[data-testid=scoreboard]"
    assert_select "meta[name=turbo-refresh-method][content=morph]"
    assert_select "meta[name=turbo-refresh-scroll][content=preserve]"
    assert_select "form[action='#{score_game_scoreboard_path(@game)}']", 0

    post score_game_scoreboard_url(@game), params: { scoreboard_id: live_id, side: "a" }
    assert_redirected_to game_scoreboard_url(@game)
    assert_empty @game.scoreboards.live.first.actions
  end

  test "trainings have no scoreboard" do
    @game.update_columns(kind: "training")

    post game_scoreboard_url(@game), params: { team_a: [ "u:#{@owner.id}" ], team_b: [ "u:#{@rival.id}" ] }

    assert_redirected_to game_scoreboard_url(@game)
    assert_empty @game.scoreboards
  end
end
