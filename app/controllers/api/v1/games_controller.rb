module Api
  module V1
    class GamesController < Api::BaseController
      def index
        games = Games::Search.new(scope: visible_games)
          .sport(params[:sport])
          .skill_level(params[:skill_level])
          .in_cities(params[:city])
          .urgent_only(params[:urgent])
          .from_date(params[:from])
          .to_date(params[:to])
          .upcoming_only(params[:upcoming].nil? || params[:upcoming].to_s == "true")
          .ordered
          .to_a

        games = Games::Search.with_spots(games) if params[:with_spots].to_s == "true"
        games = games.first(Games::Search.limit_for(params[:limit]))

        render json: { games: Games::Serializer.new(games, host: host).as_json }
      end

      def show
        game = visible_games.find(params[:id])

        render json: { game: Games::Serializer.new([ game ], host: host).as_json.first }
      end

      private

      # Корты на модерации не показываем никому: страница такой игры и на сайте
      # доступна только админу.
      def visible_games
        Game.joins(:court).merge(Court.approved)
      end

      def host
        ENV.fetch("APP_HOST", "https://getcourt.co")
      end
    end
  end
end
