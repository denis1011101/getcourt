class NotificationDelivery
  class Notification
    # parse_mode нужен тем сообщениям, где есть разметка — например ссылка на
    # корт в приглашении. Остальные остаются чистым текстом: тогда телеграму
    # нечего разбирать и нечем подавиться на имени с «&».
    attr_reader :parse_mode

    def initialize(subject:, body:, actions: [], parse_mode: nil)
      @subject = subject
      @body = body
      @actions = actions
      @parse_mode = parse_mode
    end

    def subject(locale, channel = nil)
      resolve(@subject, locale, channel)
    end

    def body(locale, channel = nil)
      resolve(@body, locale, channel)
    end

    def actions(locale, channel = nil)
      Array(resolve(@actions, locale, channel))
    end

    private

    # Текст иногда зависит от канала — например, звать человека по @нику стоит
    # только в телеграме. Старые лямбды об этом не знают и берут одну локаль.
    def resolve(value, locale, channel)
      return value unless value.respond_to?(:call)

      value.arity == 1 ? value.call(locale) : value.call(locale, channel)
    end
  end

  class TelegramAdapter
    def self.deliver(user, notification)
      locale = Telegram::I18n.locale_for(user)
      text = notification.body(locale, "telegram")
      buttons = notification.actions(locale, "telegram").each_with_index.filter_map do |action, index|
        next if action[:telegram] == false

        target = action[:callback_data] ? { callback_data: action[:callback_data] } : { url: action[:url] }
        [ action.fetch(:row, index), { text: action[:label] }.merge(target) ] if target.values.first.present?
      end
      keyboard = buttons.group_by(&:first).values.map { |row| row.map(&:last) }

      parse_mode = notification.parse_mode
      if keyboard.any?
        Telegram::Api.send_with_buttons(user.telegram_chat_id, text, keyboard, parse_mode: parse_mode)
      else
        SendTelegramNotificationJob.perform_later(user.telegram_chat_id, text, parse_mode: parse_mode)
      end
    end
  end

  class EmailAdapter
    def self.deliver(user, notification)
      return false if user.telegram_generated_email?

      locale = NotificationDelivery.email_locale(user)
      actions = notification.actions(locale, "email").filter_map do |action|
        { label: action[:label], url: action[:url] } if action[:url].present?
      end
      UserMailer.notification(
        user,
        subject: notification.subject(locale, "email"),
        body: notification.body(locale, "email"),
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
