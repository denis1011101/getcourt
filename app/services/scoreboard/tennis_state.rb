module Scoreboard
  # Счёт теннисного матча, собранный из списка розыгрышей: ["a", "b", "a", ...].
  # Состояние не хранится, а каждый раз проигрывается заново — так «−» у любой
  # стороны снимает её последнее очко даже через границу гейма или сета, и
  # табло не может разъехаться с историей.
  #
  # mode:
  #   "points" — действие «a»/«b» = розыгрыш (0-15-30-40, геймы, сеты, тай-брейк);
  #   "games"  — «a»/«b» = выигранный гейм (очки не ведут).
  # В обоих режимах «s:a»/«s:b» закрывает текущий сет в пользу стороны.
  # «g:a»/«g:b» — гейм стороне напрямую, без правил розыгрыша и без
  # автозакрытия сета: так записаны сыгранные геймы после смены настроек.
  # «fs:a»/«fs:b» — закрытие такого замороженного сета. В отличие от «s:»
  # (закрыли кнопкой) оно держится на своих геймах: «−» по гейму этого сета
  # снимает и его, и сет открывается, как при обычной игре.
  # «tb:5» — счёт тай-брейка (очки проигравшего) для сета 7:6, закрытого в
  # режиме геймов: стоит сразу за действием, закрывшим этот сет.
  class TennisState
    POINT_LABELS = %w[0 15 30 40].freeze
    SIDES = %w[a b].freeze
    MODES = %w[points games].freeze
    SET_GAMES = 6

    attr_reader :sets, :games, :points, :winner, :settings

    def initialize(settings, actions = [])
      @settings = normalize(settings)
      reset
      Array(actions).each_with_index do |action, index|
        @index = index
        apply(action.to_s)
      end
    end

    # Номер (с нуля) последнего сета 7:6, чей тай-брейк вписывают руками:
    # ещё пустой или уже записанный токеном «tb:». Тай-брейк, разыгранный в
    # полном счёте по очкам, так не правят — он часть истории розыгрышей.
    def tiebreak_editable_set
      sets.rindex { |set| seven_six?(set) && (set["tb"].nil? || set["tb_token"]) }
    end

    # Счёт тай-брейка сета по сторонам, как на табло: { "a" => 7, "b" => 5 }.
    def tiebreak_points(set)
      return nil if set["tb"].nil?

      winner = set["a"] > set["b"] ? "a" : "b"
      { winner => [ 7, set["tb"] + 2 ].max, other(winner) => set["tb"] }
    end

    # История, пересобранная под новые настройки. Сыгранное замораживается
    # явными токенами «g:» и «s:», которые проигрываются одинаково при любых
    # правилах: включённое золотое очко или выключенный тай-брейк не должны
    # переигрывать уже закончившиеся геймы и сеты. По новым правилам считается
    # только недоигранный гейм — и то в пределах 40:40, чтобы его не закрыло
    # задним числом.
    def rebuilt_actions(new_settings)
      target = normalize(new_settings)
      rebuilt = []
      sets.each do |set|
        rebuilt.concat(frozen_games(set))
        rebuilt << "fs:#{set["a"] > set["b"] ? "a" : "b"}"
        rebuilt << "tb:#{set["tb"]}" if set["tb"]
      end
      rebuilt.concat(frozen_games(games))
      rebuilt.concat(open_game_points(target)) if points_mode? && target["mode"] == "points"
      rebuilt
    end

    # Индексы действий последнего сета, выигранного стороной: «− сет» убирает
    # его целиком, вместе с геймами соперника в нём, — сета как не было.
    def last_set_range(side)
      set = sets.reverse.find { |candidate| candidate[side] > candidate[other(side)] }
      set && set["range"]
    end

    def points_mode?
      settings["mode"] == "points"
    end

    def finished?
      winner.present?
    end

    def tiebreak?
      @tiebreak
    end

    def sets_won(side)
      sets.count { |set| set[side] > set[other(side)] }
    end

    # Строка в формате формы статистики: «6-4 7-6(5)». Недоигранный сет тоже
    # попадает, если в нём уже есть геймы: матч могли закончить по времени.
    def score_string
      parts = sets.map { |set| set_string(set) }
      parts << "#{games["a"]}-#{games["b"]}" if !finished? && (games["a"] + games["b"]).positive?
      parts.join(" ")
    end

    # Итог для статистики: у кого больше сетов в строке счёта, считая и
    # недоигранный. Поровну — ничья, как и в форме.
    def result
      return winner.to_sym if finished?

      counted = sets + ((games["a"] + games["b"]).positive? ? [ games.dup ] : [])
      a = counted.count { |set| set["a"] > set["b"] }
      b = counted.count { |set| set["b"] > set["a"] }
      return :draw if a == b

      a > b ? :a : :b
    end

    # Подписи очков текущего гейма: 0/15/30/40/AD, в тай-брейке — числа.
    def point_label(side)
      return points[side].to_s if tiebreak?

      mine = points[side]
      theirs = points[other(side)]
      if mine >= 3 && theirs >= 3
        return "AD" if mine > theirs
        return "40"
      end
      POINT_LABELS.fetch(mine, "40")
    end

    private

    def normalize(settings)
      settings = settings.to_h.stringify_keys
      {
        "mode" => MODES.include?(settings["mode"].to_s) ? settings["mode"].to_s : "points",
        "sets_to_win" => settings["sets_to_win"].to_i.clamp(1, 3),
        "tiebreak" => ActiveModel::Type::Boolean.new.cast(settings.fetch("tiebreak", true)),
        "golden_point" => ActiveModel::Type::Boolean.new.cast(settings.fetch("golden_point", false))
      }
    end

    def reset
      @set_start = 0
      @sets = []
      @games = { "a" => 0, "b" => 0 }
      @points = { "a" => 0, "b" => 0 }
      @tiebreak = false
      @winner = nil
    end

    def apply(action)
      return attach_tiebreak(action.delete_prefix("tb:").to_i) if finished? && action.start_with?("tb:")
      return if finished?

      if action.start_with?("tb:")
        attach_tiebreak(action.delete_prefix("tb:").to_i)
      elsif action.start_with?("g:")
        side = action.delete_prefix("g:")
        credit_game(side) if SIDES.include?(side)
      elsif action.start_with?("s:", "fs:")
        side = action.split(":", 2).last
        award_set(side) if SIDES.include?(side)
      elsif SIDES.include?(action)
        points_mode? ? win_point(action) : win_game(action)
      end
    end

    def attach_tiebreak(loser_points)
      set = sets.last
      return unless set && set["tb"].nil? && seven_six?(set)

      set["tb"] = loser_points
      set["tb_token"] = @index
      set["range"] = (set["range"].begin..@index)
      @set_start = @index + 1
    end

    def credit_game(side)
      @points = { "a" => 0, "b" => 0 }
      games[side] += 1
      # 6:6 из замороженных геймов в полном счёте — дальше идёт тай-брейк.
      @tiebreak = settings["tiebreak"] && points_mode? && games["a"] == SET_GAMES && games["b"] == SET_GAMES
    end

    def frozen_games(set)
      [ "g:a" ] * set["a"] + [ "g:b" ] * set["b"]
    end

    # Очки недоигранного гейма. Тай-брейк переносим, только если он и по новым
    # правилам идёт; «больше» при 40:40 сводим к ровно, если теперь золотое
    # очко (иначе оно закрыло бы гейм), а в остальном очки остаются как были.
    def open_game_points(target)
      return [] if tiebreak? && !(target["tiebreak"] && games["a"] == SET_GAMES && games["b"] == SET_GAMES)
      return [] if !tiebreak? && target["tiebreak"] && games["a"] == SET_GAMES && games["b"] == SET_GAMES

      a = points["a"]
      b = points["b"]
      unless tiebreak?
        if a >= 3 && b >= 3
          lead = target["golden_point"] ? 0 : (a <=> b)
          a = 3 + [ lead, 0 ].max
          b = 3 + [ -lead, 0 ].max
        end
      end
      alternate(a, b)
    end

    def alternate(a, b)
      shared = [ a, b ].min
      ([ "a", "b" ] * shared) + [ "a" ] * (a - shared) + [ "b" ] * (b - shared)
    end

    # Сет закрывают вручную: с набранными геймами, если сторона ведёт, а если
    # нет — с минимальным перевесом в один гейм. Шестёрки не придумываем: в
    # статистику уйдёт то, что было на корте.
    def award_set(side)
      games[side] = games[other(side)] + 1 if games[side] <= games[other(side)]
      @points = { "a" => 0, "b" => 0 }
      @tiebreak = false
      close_set(nil)
    end

    def win_point(side)
      points[side] += 1
      mine = points[side]
      theirs = points[other(side)]

      if tiebreak?
        win_tiebreak(side) if mine >= 7 && mine - theirs >= 2
      elsif settings["golden_point"] && mine >= 4 && theirs == 3
        win_game(side)
      elsif mine >= 4 && mine - theirs >= 2
        win_game(side)
      end
    end

    def win_game(side)
      @points = { "a" => 0, "b" => 0 }
      games[side] += 1
      mine = games[side]
      theirs = games[other(side)]

      if mine >= SET_GAMES && mine - theirs >= 2
        close_set(nil)
      elsif settings["tiebreak"] && mine == SET_GAMES && theirs == SET_GAMES && points_mode?
        @tiebreak = true
      elsif settings["tiebreak"] && mine == SET_GAMES + 1 && theirs == SET_GAMES
        # В режиме геймов тай-брейк не разыгрывают по очкам: 13-й гейм и есть он.
        close_set(nil)
      end
    end

    def win_tiebreak(side)
      loser_points = points[other(side)]
      @points = { "a" => 0, "b" => 0 }
      @tiebreak = false
      games[side] += 1
      close_set(loser_points)
    end

    def close_set(tiebreak_points)
      sets << games.merge("tb" => tiebreak_points, "range" => (@set_start..@index))
      @set_start = @index + 1
      @games = { "a" => 0, "b" => 0 }
      SIDES.each { |side| @winner = side if sets_won(side) >= settings["sets_to_win"] }
    end

    def seven_six?(set)
      [ set["a"], set["b"] ].sort == [ SET_GAMES, SET_GAMES + 1 ]
    end

    def set_string(set)
      tb = set["tb"].nil? ? "" : "(#{set["tb"]})"
      "#{set["a"]}-#{set["b"]}#{tb}"
    end

    def other(side)
      side == "a" ? "b" : "a"
    end
  end
end
