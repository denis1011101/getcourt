class NotificationDelivery
  def self.deliver(user:, telegram_text:, email_subject:, email_body:, actions: [], telegram_buttons: nil)
    case user.notification_channel
    when "telegram"
      return false unless user.telegram_chat_id.present?

      if telegram_buttons.present?
        Telegram::Api.send_with_buttons(user.telegram_chat_id, telegram_text, telegram_buttons, parse_mode: nil)
      else
        SendTelegramNotificationJob.perform_later(user.telegram_chat_id, telegram_text, parse_mode: nil)
      end
    when "email"
      UserMailer.notification(
        user,
        subject: email_subject,
        body: email_body,
        actions: actions
      ).deliver_later
    end
  end

  def self.email_locale(user)
    user.locale.to_s.presence_in(User::WEB_LOCALES) || I18n.default_locale
  end
end
