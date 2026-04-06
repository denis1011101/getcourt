class FavoriteCourt < ApplicationRecord
  belongs_to :user
  belongs_to :court

  validates :court_id, uniqueness: { scope: :user_id }
end
