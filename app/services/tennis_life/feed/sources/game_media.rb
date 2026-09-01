module TennisLife
  module Feed
    module Sources
      class GameMedia < Base
        # Инфлектор превратил бы "game_media" в "game_medium" — прибиваем вид
        # карточки явно, чтобы имя партиала и ветка в Loader не разъезжались.
        def kind
          "game_media"
        end

        def ids
          # Здесь загрузка и есть событие, поэтому дата события — created_at,
          # а не отдельная колонка, как у матчей или постов.
          recent(snapshotted(::GameMedium.visible.in_feed), column: :created_at)
            .joins(:game)
            .where(games: { tournament_id: nil })
            .pluck(:id)
        end

        def weight
          0.7
        end
      end
    end
  end
end
