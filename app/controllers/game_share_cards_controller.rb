class GameShareCardsController < ApplicationController
  skip_before_action :authenticate_user!, only: :show

  def show
    game = Game.includes(:court, :participations).find(params[:game_id])
    locale = telegram_locale
    path = Telegram::Helpers::GameCardRenderer.render(game, locale: locale)

    send_data File.binread(path),
      filename: "getcourt-game-#{game.id}.png",
      type: "image/png",
      disposition: "inline"
  ensure
    File.delete(path) if path.present? && File.exist?(path)
  end

  private

  def telegram_locale
    locale = I18n.locale.to_s
    return locale if Telegram::I18n::LOCALES.include?(locale)

    default_locale = I18n.default_locale.to_s
    Telegram::I18n::LOCALES.include?(default_locale) ? default_locale : Telegram::I18n::DEFAULT_LOCALE
  end
end
