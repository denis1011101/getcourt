class Participation < ApplicationRecord
  belongs_to :game
  belongs_to :user, optional: true

  enum :status, { pending: "pending", approved: "approved" }

  validates :user_id, uniqueness: { scope: :game_id, message: "has already joined this game" }, allow_nil: true
  validates :user, presence: true, if: -> { user_id.present? }
  validates :status, presence: true
  validates :guest_name, presence: true, length: { maximum: 50 }, if: -> { user_id.blank? }
  validates :guest_name, absence: true, if: -> { user_id.present? }
  validates :guest_name, uniqueness: { scope: :game_id, case_sensitive: false }, allow_blank: true

  scope :guests, -> { where(user_id: nil) }

  # Выбыл из состава — режим чата этой игры гасим: писать в неё он больше не
  # вправе, и указатель не должен переживать участие.
  after_destroy :close_game_chat
  after_update :close_game_chat, if: -> { saved_change_to_status? && !approved? }

  def guest?
    user_id.nil?
  end

  def close_game_chat
    Telegram::Chat::Session.stop_for(user, game)
  rescue StandardError => e
    Rails.logger.warn("[Participation##{id}] chat session cleanup failed: #{e.class}: #{e.message}")
  end

  def display_name
    guest? ? guest_name : (user.name.presence || user.email)
  end
end
