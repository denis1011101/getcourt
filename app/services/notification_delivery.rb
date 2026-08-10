class NotificationDelivery
  class Notification
    def initialize(subject:, body:, actions: [])
      @subject = subject
      @body = body
      @actions = actions
    end

    def subject(locale)
      resolve(@subject, locale)
    end

    def body(locale)
      resolve(@body, locale)
    end

    def actions(locale)
      Array(resolve(@actions, locale))
    end

    private

    def resolve(value, locale)
      value.respond_to?(:call) ? value.call(locale) : value
    end
  end

  class TelegramAdapter
    def self.deliver(user, notification)
      locale = Telegram::I18n.locale_for(user)
      text = notification.body(locale)
      buttons = notification.actions(locale).each_with_index.filter_map do |action, index|
        next if action[:telegram] == false

        target = action[:callback_data] ? { callback_data: action[:callback_data] } : { url: action[:url] }
        [ action.fetch(:row, index), { text: action[:label] }.merge(target) ] if target.values.first.present?
      end
      keyboard = buttons.group_by(&:first).values.map { |row| row.map(&:last) }

      if keyboard.any?
        Telegram::Api.send_with_buttons(user.telegram_chat_id, text, keyboard, parse_mode: nil)
      else
        SendTelegramNotificationJob.perform_later(user.telegram_chat_id, text, parse_mode: nil)
      end
    end
  end

  class EmailAdapter
    def self.deliver(user, notification)
      return false if user.telegram_generated_email?

      locale = NotificationDelivery.email_locale(user)
      actions = notification.actions(locale).filter_map do |action|
        { label: action[:label], url: action[:url] } if action[:url].present?
      end
      UserMailer.notification(
        user,
        subject: notification.subject(locale),
        body: notification.body(locale),
        actions: actions
      ).deliver_later
    end
  end

  ADAPTERS = {
    "email" => EmailAdapter,
    "telegram" => TelegramAdapter
  }.freeze

  def self.deliver(user:, notification:)
    channel = user.notification_channel.to_s
    channel = "email" if channel == "telegram" && user.telegram_chat_id.blank?
    adapter = ADAPTERS[channel]
    adapter&.deliver(user, notification)
  end

  def self.email_locale(user)
    user.locale.to_s.presence_in(User::WEB_LOCALES) || ::I18n.default_locale
  end
end
