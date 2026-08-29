class CourtSuggestion < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze
  EDITABLE_FIELDS = %w[name sport coordinates contact_type contact_value free outdoor indoor sauna surfaces].freeze

  belongs_to :court
  belongs_to :user
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: {
    scope: :court_id,
    conditions: -> { where(status: "pending") },
    message: :pending_exists
  }
  validate :payload_present, on: :create
  validate :payload_fields_are_editable

  scope :pending, -> { where(status: "pending") }

  def pending?
    status == "pending"
  end

  def apply_by!(admin)
    return false unless admin&.admin?

    with_lock do
      return false unless pending?

      court.assign_attributes(payload.slice(*EDITABLE_FIELDS))
      unless court.valid?
        court.errors.full_messages.each { |message| errors.add(:base, message) }
        return false
      end

      court.save!
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

  private

  # Комментарий остался только у записей, созданных до того, как поле убрали из формы,
  # поэтому новое предложение обязано менять хотя бы одно поле. Проверяем на создании:
  # иначе модератор не смог бы одобрить или отклонить давнее предложение без правок.
  def payload_present
    errors.add(:base, :blank_suggestion) if payload.blank?
  end

  def payload_fields_are_editable
    unless payload.is_a?(Hash)
      errors.add(:payload, :invalid_fields)
      return
    end

    invalid_fields = payload.to_h.keys.map(&:to_s) - EDITABLE_FIELDS
    errors.add(:payload, :invalid_fields) if invalid_fields.any?
  end
end
