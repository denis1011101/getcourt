class GameShareCardsController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  def show
    game = Game.includes(:court, :tournament, :participations).find(params[:game_id])
    data = Games::ShareCardRenderer.render_data(game, locale: I18n.locale)

    send_data data,
      filename: "getcourt-game-#{game.id}.png",
      type: "image/png",
      disposition: "inline"
  end
end
