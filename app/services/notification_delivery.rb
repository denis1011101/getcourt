class NotificationDelivery
  def self.deliver(user:, telegram_text:, email_subject:, email_body:, actions: [], telegram_buttons: nil)
    case user.notification_channel
    when "telegram"
      if user.telegram_chat_id.present?
        if telegram_buttons.present?
          Telegram::Api.send_with_buttons(user.telegram_chat_id, telegram_text, telegram_buttons, parse_mode: nil)
        else
          SendTelegramNotificationJob.perform_later(user.telegram_chat_id, telegram_text, parse_mode: nil)
        end
      else
        deliver_email(user, email_subject, email_body, actions)
      end
    when "email"
      deliver_email(user, email_subject, email_body, actions)
    end
  end

  def self.email_locale(user)
    user.locale.to_s.presence_in(User::WEB_LOCALES) || I18n.default_locale
  end

  def self.deliver_email(user, subject, body, actions)
    return false if user.telegram_generated_email?

    UserMailer.notification(user, subject: subject, body: body, actions: actions).deliver_later
  end
  private_class_method :deliver_email
end
