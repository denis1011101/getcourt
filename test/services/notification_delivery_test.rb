require "test_helper"

class NotificationDeliveryTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "does not send email to a generated telegram address" do
    user = User.create!(
      email: "tg-#{SecureRandom.hex(8)}@telegram.getcourt",
      telegram_generated_email: true,
      notification_channel: "email"
    )

    assert_no_enqueued_emails do
      assert_not NotificationDelivery.deliver(**delivery_arguments(user))
    end
  ensure
    user&.destroy
  end

  test "falls back to email when telegram is selected but not connected" do
    user = User.create!(
      email: "notification-fallback@example.com",
      notification_channel: "telegram"
    )

    assert_enqueued_emails 1 do
      NotificationDelivery.deliver(**delivery_arguments(user))
    end
  ensure
    user&.destroy
  end

  test "does not enqueue an email for a user without an address" do
    # Раньше письмо уходило в очередь и падало уже там («SMTP To address may not
    # be blank»), а отправитель успевал отчитаться об успешной доставке.
    # Записи без email в базе есть: бот заводит их через save(validate: false).
    user = User.new(notification_channel: "telegram")
    user.save(validate: false)

    assert_no_enqueued_emails do
      assert_not NotificationDelivery.deliver(**delivery_arguments(user))
    end
  ensure
    user&.destroy
  end

  private

  def delivery_arguments(user)
    {
      user: user,
      notification: NotificationDelivery::Notification.new(
        subject: "Email subject",
        body: "Notification body"
      )
    }
  end
end
