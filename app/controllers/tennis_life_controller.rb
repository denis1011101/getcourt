class TennisLifeController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index ]

  TELEGRAM_CHANNELS = [
    { name: "Ноги Руне 🎾🎾🎾", username: "@nogirune", url: "https://t.me/nogirune" },
    { name: "Теннисология", username: "@getcourt", url: "https://t.me/tennisologia" },
    { name: "Теннис+", username: "@tennispls", url: "https://t.me/tennispls" },
    { name: "ТеннисДрот", username: "@tennisdrot", url: "https://t.me/tennisdrot" }
  ].freeze

  def index
    # view will provide SEO content_for
  end
end
