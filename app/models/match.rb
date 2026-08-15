class Match < ApplicationRecord
  belongs_to :user
  belongs_to :opponent, class_name: "User", optional: true
  belongs_to :game, optional: true

  MODES = %w[singles doubles].freeze
  OUTCOMES = %w[win loss draw].freeze
  SURFACES = %w[hard clay grass carpet indoor_hard other].freeze

  validates :mode, inclusion: { in: MODES }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :surface, inclusion: { in: SURFACES }, allow_nil: true
  validates :played_at, presence: true

  # Ссылку на карточку игры показываем, только пока карточка описывает именно
  # этот матч (см. Game#covers_moment?). Удалённая игра сюда не доедет:
  # dependent: :nullify обнуляет game_id, и остаётся просто карточка со счётом.
  def game_page_relevant?
    game.present? && game.covers_moment?(played_at)
  end
end
