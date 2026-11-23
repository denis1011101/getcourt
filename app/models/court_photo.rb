class CourtPhoto < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze
  ACTIVE_STATUSES = %w[pending approved].freeze
  IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_IMAGE_SIZE = 5.megabytes
  MAX_PHOTOS_PER_COURT = 3

  belongs_to :court
  belongs_to :user
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }
  validate :file_attached
  validate :supported_content_type
  validate :within_size_limit
  validate :within_court_limit, on: :create

  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :ordered, -> { order(created_at: :asc, id: :asc) }

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def approve_by!(admin)
    return false unless admin&.admin?

    court.with_lock do
      reload
      return false unless pending?

      if court.court_photos.approved.count >= MAX_PHOTOS_PER_COURT
        errors.add(:base, :court_limit_reached, count: MAX_PHOTOS_PER_COURT)
        return false
      end

      update!(status: "approved", reviewed_by: admin, reviewed_at: Time.current)
    end
    true
  end

  def reject_by!(admin)
    return false unless admin&.admin?

    with_lock do
      return false unless pending?

      update!(status: "rejected", reviewed_by: admin, reviewed_at: Time.current)
    end
    true
  end

  def display_variant
    return nil unless file.attached?

    file.variant(resize_to_limit: [ 1200, 900 ]).processed
  rescue StandardError => e
    Rails.logger.warn("[CourtPhoto##{id}] variant failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def content_type
    file.attached? ? file.blob.content_type : nil
  end

  def file_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def supported_content_type
    return unless file.attached?
    return if IMAGE_TYPES.include?(content_type)

    errors.add(:file, :invalid_type)
  end

  def within_size_limit
    return unless file.attached?
    return if file.blob.byte_size <= MAX_IMAGE_SIZE

    errors.add(:file, :too_large)
  end

  def within_court_limit
    return unless court

    active_count = court.court_photos.where(status: ACTIVE_STATUSES).count
    return if active_count < MAX_PHOTOS_PER_COURT

    errors.add(:base, :court_limit_reached, count: MAX_PHOTOS_PER_COURT)
  end
end
