module TennisLife
  module Feed
    module Sources
      # По карточке на турнир табло, а не одно табло целиком: так они
      # разбредаются по ленте, как остальные посты. Ведущий турнир Builder
      # закрепляет в начале первой страницы. Табло берём по снимку курсора,
      # а не живое — см. TennisScoreboard::Board.at.
      class Scoreboard < Base
        def ids
          TennisScoreboard::Board.at(snapshot_ts).tournaments.map(&:slug)
        end

        def weight
          2.5
        end
      end
    end
  end
end
