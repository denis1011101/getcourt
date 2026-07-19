class FeaturedMatch < ApplicationRecord
  STATUSES = %w[scheduled live finished].freeze
  EVENT_STATUS_SCHEMA = {
    "scheduled" => "https://schema.org/EventScheduled",
    "live" => "https://schema.org/EventScheduled",
    "finished" => "https://schema.org/EventScheduled"
  }.freeze

  belongs_to :court, optional: true

  has_many_attached :photos

  scope :current, -> { where(active: true).where("starts_at > ?", Time.current).order(:starts_at).limit(1) }
  # The active match shown in the site banner. Unlike `current`, it keeps
  # returning the match after kickoff (and once finished) so the banner can show
  # "match started" / "match finished" until it is deactivated (active: false).
  scope :banner, -> { where(active: true).order(:starts_at).limit(1) }
  scope :archive, -> { where(active: false).order(starts_at: :desc) }

  validates :tournament_label, :player_left_name, :player_right_name, :starts_at, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :status, inclusion: { in: STATUSES }

  before_validation :generate_slug, on: :create
  before_save :deactivate_other_matches, if: -> { active? && (new_record? || will_save_change_to_active?) }

  def seo_title
    "#{player_left_name} vs #{player_right_name} · #{tournament_label}"
  end

  def seo_description
    if status == "finished"
      I18n.t("featured_match.seo.finished", title: seo_title, result: result.presence || I18n.t("featured_match.seo.result_pending"))
    elsif starts_at <= Time.current
      I18n.t("featured_match.seo.started", title: seo_title)
    else
      I18n.t("featured_match.seo.scheduled", title: seo_title, date: I18n.l(starts_at.to_date, format: :long))
    end
  end

  def to_param
    slug
  end

  def event_status_schema
    EVENT_STATUS_SCHEMA.fetch(status, EVENT_STATUS_SCHEMA["scheduled"])
  end

  def og_image_url(host: nil, protocol: nil)
    return nil unless photos.attached? && host.present?

    variant = photos.first.variant(resize_to_limit: [ 1200, 630 ]).processed
    Rails.application.routes.url_helpers.rails_representation_url(variant, host: host, protocol: protocol)
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = [
      tournament_label,
      starts_at&.year,
      player_left_name,
      player_right_name
    ].compact.join(" ").parameterize.presence || "featured-match"

    candidate = base_slug
    suffix = 2
    while FeaturedMatch.where.not(id: id).exists?(slug: candidate)
      candidate = "#{base_slug}-#{suffix}"
      suffix += 1
    end

    self.slug = candidate
  end

  def deactivate_other_matches
    matches = FeaturedMatch.where(active: true)
    matches = matches.where.not(id: id) if id.present?
    matches.update_all(active: false, updated_at: Time.current)
  end
end
