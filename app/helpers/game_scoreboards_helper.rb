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
    settings = scoreboard.state.settings
    parts = [
      t("game_scoreboards.setup.mode_#{settings["mode"]}"),
      t("game_scoreboards.setup.sets_option", count: settings["sets_to_win"])
    ]
    parts << t("game_scoreboards.setup.tiebreak") if settings["tiebreak"]
    parts << t("game_scoreboards.setup.golden_point") if settings["golden_point"] && settings["mode"] == "points"
    parts.join(" · ")
  end

  # Что стоит в форме настройки: отправленное (после ошибки), иначе текущие
  # настройки идущего матча, иначе умолчания нового.
  def scoreboard_form_values(scoreboard, params)
    if params[:settings].present?
      settings = Scoreboard::TennisState.new(params[:settings].to_unsafe_h.transform_values { |value| value == "0" ? false : value }).settings
      return { "team_a" => Array(params[:team_a]), "team_b" => Array(params[:team_b]), settings: settings }
    end

    if scoreboard&.persisted?
      team = ->(data) { Array(data["user_ids"]).map { |id| "u:#{id}" } + Array(data["guest_names"]).map { |name| "g:#{name}" } }
      return { "team_a" => team.(scoreboard.team_a), "team_b" => team.(scoreboard.team_b), settings: scoreboard.state.settings }
    end

    { "team_a" => [], "team_b" => [], settings: Scoreboard::TennisState.new({}).settings }
  end
end
