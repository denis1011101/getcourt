class SendTrainingVideoJob < ApplicationJob
  queue_as :default

  def perform(game_medium_id)
    medium = GameMedium.includes(file_attachment: :blob).find_by(id: game_medium_id)
    return unless medium&.video? && !medium.hidden?

    notification = build_notification(medium)
    medium.game.participations.approved.where.not(user_id: nil).includes(:user).find_each do |participation|
      NotificationDelivery.deliver(user: participation.user, notification: notification)
    rescue StandardError => e
      Rails.logger.warn("SendTrainingVideoJob failed for user_id=#{participation.user_id}: #{e.message}")
    end
  end

  private

  def build_notification(medium)
    url = Rails.application.routes.url_helpers.rails_blob_url(
      medium.file,
      **Rails.application.config.action_mailer.default_url_options.to_h.symbolize_keys
    )

    NotificationDelivery::Notification.new(
      subject: ->(locale) { I18n.t("game_media.training_video.subject", locale: locale) },
      body: ->(locale) { I18n.t("game_media.training_video.body", locale: locale) },
      actions: lambda { |locale|
        [ { label: I18n.t("game_media.training_video.action", locale: locale), url: url } ]
      }
    )
  end
end
