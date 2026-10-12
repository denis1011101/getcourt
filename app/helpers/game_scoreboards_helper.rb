module GameScoreboardsHelper
  # Кого можно поставить на сторону табло: организатор, одобренные участники
  # и гости игры — тот же круг, что в форме статистики.
  def scoreboard_candidates(game)
    approved = game.participations.approved
    users = ([ game.user ] + approved.includes(:user).map(&:user)).compact.uniq(&:id)
    users + approved.guests.map(&:guest_name).compact_blank.uniq
  end

  def scoreboard_candidate_options(game)
    scoreboard_candidates(game).map do |player|
      player.is_a?(User) ? [ user_display_label(player), "u:#{player.id}" ] : [ "#{player} (#{t("games.show.guest_badge")})", "g:#{player}" ]
    end
  end

  # Короткая подпись на табло: места мало, поэтому имя, а ник — только если
  # имени нет.
  def scoreboard_player_label(player)
    return player if player.is_a?(String)

    player.name.presence || user_display_label(player)
  end

  # «Полный счёт · до 2 сетов · тай-брейк» — чтобы по ходу матча было видно,
  # по каким правилам считает табло.
  def scoreboard_settings_summary(scoreboard)
    return t("game_scoreboards.setup.kind_one_vs_two") if scoreboard.one_vs_two?

    settings = scoreboard.state.settings
    parts = [
      t("game_scoreboards.setup.mode_#{settings["mode"]}"),
      t("game_scoreboards.setup.sets_option", count: settings["sets_to_win"])
    ]
    parts << t("game_scoreboards.setup.tiebreak") if settings["tiebreak"]
    parts << t("game_scoreboards.setup.golden_point") if settings["golden_point"] && settings["mode"] == "points"
    parts.unshift(t("game_scoreboards.series.number", number: scoreboard.series_index + 1, total: GameScoreboard::SERIES_PAIRS.size)) if scoreboard.round_robin?
    parts.join(" · ")
  end

  # Что стоит в форме настройки: отправленное (после ошибки), иначе текущие
  # настройки идущего матча, иначе умолчания нового.
  def scoreboard_form_values(scoreboard, params)
    if params[:settings].present?
      settings = Scoreboard::TennisState.new(params[:settings].to_unsafe_h.transform_values { |value| value == "0" ? false : value }).settings
      return { "team_a" => Array(params[:team_a]), "team_b" => Array(params[:team_b]), "trio" => Array(params[:trio]),
               "kind" => params[:settings][:kind].to_s.presence || "match", settings: settings }
    end

    if scoreboard&.persisted?
      team = ->(data) { Array(data["user_ids"]).map { |id| "u:#{id}" } + Array(data["guest_names"]).map { |name| "g:#{name}" } }
      return { "team_a" => team.(scoreboard.team_a), "team_b" => team.(scoreboard.team_b), "trio" => scoreboard.trio,
               "kind" => scoreboard.kind, settings: scoreboard.state.settings }
    end

    { "team_a" => [], "team_b" => [], "trio" => [], "kind" => "match", settings: Scoreboard::TennisState.new({}).settings }
  end

  def scoreboard_names(players)
    players.map { |player| scoreboard_player_label(player) }.join(" / ")
  end

  # Серия втроём: три пары по порядку — со счётом, идущая или ещё впереди, —
  # и таблица по победам (при равенстве — по выигранным геймам).
  def scoreboard_series(scoreboard)
    boards = scoreboard.series_scoreboards
    players = scoreboard.trio_players
    wins = Array.new(players.size, 0)
    games = Array.new(players.size, 0)

    rows = GameScoreboard::SERIES_PAIRS.each_with_index.map do |(first, second), index|
      board = boards[index]
      status = board.nil? ? :upcoming : (board.live? ? :live : :finished)
      state = board&.state
      if status == :finished && state.score_string.present?
        result = state.result
        wins[first] += 1 if result == :a
        wins[second] += 1 if result == :b
        games[first] += scoreboard_games_won(state, "a")
        games[second] += scoreboard_games_won(state, "b")
      end
      { names: "#{scoreboard_player_label(players[first])} — #{scoreboard_player_label(players[second])}",
        status: status, score: state&.score_string.presence }
    end

    standings = players.each_index.sort_by { |index| [ -wins[index], -games[index], index ] }
                       .map { |index| { name: scoreboard_player_label(players[index]), wins: wins[index], games: games[index] } }
    { rows: rows, standings: standings, done: rows.all? { |row| row[:status] == :finished } }
  end

  private

  def scoreboard_games_won(state, side)
    state.sets.sum { |set| set[side] } + (state.finished? ? 0 : state.games[side])
  end
end
