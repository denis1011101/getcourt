class SendTrainingVideoJob < ApplicationJob
  queue_as :default

  # Отправка идёт по одной задаче на получателя: временный отказ почты или
  # телеграма роняет только свою доставку, она уходит в ретрай, а исчерпав
  # попытки — в failed jobs. Общий rescue вместо этого молча терял игрока.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(game_medium_id, user_id = nil)
    medium = GameMedium.includes(file_attachment: :blob).find_by(id: game_medium_id)
    return unless medium&.video? && !medium.hidden?

    return deliver(medium, user_id) if user_id

    medium.game.participations.approved.where.not(user_id: nil).find_each do |participation|
      self.class.perform_later(game_medium_id, participation.user_id)
    end
  end

  private

  def deliver(medium, user_id)
    user = User.find_by(id: user_id)
    return unless user

    NotificationDelivery.deliver(user: user, notification: build_notification(medium))
  end

  def build_notification(medium)
    url = Rails.application.routes.url_helpers.rails_blob_url(
      medium.file,
      **Rails.application.config.action_mailer.default_url_options.to_h.symbolize_keys
    )
    # Ролик может выложить не только организатор, но и админ или принятый
    # тренер, поэтому имя берём из самой загрузки. Без имени и ника —
    # нейтральный текст: приписывать видео организатору наугад нельзя.
    author = medium.user&.broadcast_label
    title = medium.title.presence
    # Четыре формулировки вместо склейки из кусков: подставлять имя и название
    # в обрубки фразы — значит ломать порядок слов в других языках.
    key = "game_media.shared_video.body"
    key += "_by" if author
    key += "_titled" if title

    NotificationDelivery::Notification.new(
      subject: ->(locale) { I18n.t("game_media.shared_video.subject", locale: locale) },
      body: ->(locale) { I18n.t(key, author: author, title: title, locale: locale) },
      actions: lambda { |locale|
        [ { label: I18n.t("game_media.shared_video.action", locale: locale), url: url } ]
      }
    )
  end
end
