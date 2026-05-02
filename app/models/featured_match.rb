class FeaturedMatch < ApplicationRecord
  belongs_to :court, optional: true

  has_many_attached :photos

  scope :current, -> { where(active: true).where("starts_at > ?", Time.current).order(:starts_at).limit(1) }

  validates :tournament_label, :player_left_name, :player_right_name, :starts_at, presence: true

  before_save :deactivate_other_matches, if: -> { active? && (new_record? || will_save_change_to_active?) }

  def seo_title
    "#{player_left_name} vs #{player_right_name} · #{tournament_label}"
  end

  def seo_description
    if starts_at <= Time.current
      I18n.t("featured_match.seo.started", title: seo_title)
    else
      I18n.t("featured_match.seo.scheduled", title: seo_title, date: I18n.l(starts_at.to_date, format: :long))
    end
  end

  def og_image_url(host: nil, protocol: nil)
    return nil unless photos.attached? && host.present?

    variant = photos.first.variant(resize_to_limit: [ 1200, 630 ]).processed
    Rails.application.routes.url_helpers.rails_representation_url(variant, host: host, protocol: protocol)
  end

  private

  def deactivate_other_matches
    matches = FeaturedMatch.where(active: true)
    matches = matches.where.not(id: id) if id.present?
    matches.update_all(active: false, updated_at: Time.current)
  end
end
