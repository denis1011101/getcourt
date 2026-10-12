module Scoreboard
  # Счёт «2 против 1» втроём: играют по одному гейму, один игрок против
  # двоих, и одиночка меняется по кругу — первый, второй, третий, снова
  # первый. Каждое действие — итог гейма. Одиночке идёт в зачёт только
  # выигранный им гейм, у кого таких
  # больше к концу — тот и победил. Конца по счёту нет: игру закрывают
  # кнопкой, когда наиграются.
  #
  # «w:1» — гейм в одиночку взял игрок 1 (у каждого свой «+»), после него
  # один — следующий по кругу. «l» — гейм взяла пара. «w» без номера —
  # старая запись: гейм взял тот, чья была очередь.
  class OneVsTwoState
    PLAYERS = 3

    attr_reader :games, :solo_wins, :solo_played, :solo_index, :winners

    def initialize(actions = [])
      @games = Array(actions).map(&:to_s).select { |action| action.match?(/\A(w(:[0-2])?|l)\z/) }
      @solo_wins = Array.new(PLAYERS, 0)
      @solo_played = Array.new(PLAYERS, 0)
      @solo_index = 0
      # Кому засчитан каждый гейм истории (nil — паре): по нему «−» у игрока
      # находит его последний гейм.
      @winners = games.map { |action| apply(action) }
    end

    def games_played
      games.size
    end

    # Лидеры — все, у кого максимум. Пока геймов нет — никого.
    def leaders
      return [] if games_played.zero?

      top = solo_wins.max
      (0...PLAYERS).select { |index| solo_wins[index] == top }
    end

    # Игроки от лучшего к худшему; при равенстве — по порядку ротации.
    def ranking
      wins = solo_wins
      (0...PLAYERS).sort_by { |index| [ -wins[index], index ] }
    end

    def score_string
      return "" if games_played.zero?

      ranking.map { |index| solo_wins[index] }.join("-")
    end

    # Итог для статистики: единственный лидер — win, делёж первого места —
    # draw, остальные — loss. Все трое поровну — ничья у всех.
    def outcome(index)
      return "draw" if leaders.size == PLAYERS
      return "loss" unless leaders.include?(index)

      leaders.size == 1 ? "win" : "draw"
    end

    def finished?
      false
    end

    private

    def apply(action)
      player = action == "l" ? nil : (action.include?(":") ? action.split(":").last.to_i : solo_index)
      solo = player || solo_index
      solo_played[solo] += 1
      solo_wins[solo] += 1 if player
      @solo_index = (solo + 1) % PLAYERS
      player
    end
  end
end
