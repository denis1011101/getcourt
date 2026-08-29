class CourtRating < ApplicationRecord
  VALUES = (1..5).to_a.freeze

  belongs_to :court
  belongs_to :user

  validates :value, inclusion: { in: VALUES }
  validates :user_id, uniqueness: { scope: :court_id }

  after_commit :refresh_court_rating

  private

  def refresh_court_rating
    # Корт уходит вместе со своими оценками, и обновлять счётчик на удалённой
    # записи уже нечем — dependent: :destroy доводит нас сюда после её удаления.
    court.refresh_rating! unless court.destroyed?
  end
end
