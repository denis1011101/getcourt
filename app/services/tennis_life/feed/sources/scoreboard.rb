module TennisLife
  module Feed
    module Sources
      # По карточке на турнир табло, а не одно табло целиком: так они
      # разбредаются по ленте, как остальные посты. Ведущий турнир Builder
      # закрепляет в начале первой страницы.
      class Scoreboard < Base
        def ids
          TennisScoreboard::Board.current.tournaments.map(&:slug)
        end

        def weight
          2.5
        end
      end
    end
  end
end
