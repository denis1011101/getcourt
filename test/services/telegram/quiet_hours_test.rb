require "test_helper"

class TelegramQuietHoursTest < ActiveSupport::TestCase
  include StubHelper

  setup do
    @user = User.create!(
      email: "quiet-hours@example.com",
      telegram_chat_id: 920_100_001,
      timezone: "Asia/Yekaterinburg"
    )
  end

  test "night in the recipient's own timezone silences the message" do
    # 23:00 UTC — это четыре утра в Екатеринбурге: ровно тот час, в который
    # приходила карточка чата.
    travel_to Time.utc(2026, 9, 5, 23, 0) do
      assert Telegram::QuietHours.silent?(@user.telegram_chat_id)
    end
  end

  test "daytime in the recipient's own timezone keeps the sound" do
    travel_to Time.utc(2026, 9, 5, 7, 0) do
      assert_not Telegram::QuietHours.silent?(@user.telegram_chat_id)
    end
  end

  # Час считаем у получателя, а не у сервера: одна и та же минута рассылки для
  # одного человека день, для другого ночь.
  test "the same moment is loud for one recipient and silent for another" do
    @user.update!(timezone: "America/Los_Angeles")
    at = Time.utc(2026, 9, 5, 23, 0)

    assert_not Telegram::QuietHours.silent?(@user.telegram_chat_id, at: at)

    @user.update!(timezone: "Asia/Yekaterinburg")
    assert Telegram::QuietHours.silent?(@user.telegram_chat_id, at: at)
  end

  test "the loud window opens at ten and closes at twenty two" do
    zone = ActiveSupport::TimeZone["Asia/Yekaterinburg"]

    assert Telegram::QuietHours.silent?(@user.telegram_chat_id, at: zone.parse("2026-09-05 09:59"))
    assert_not Telegram::QuietHours.silent?(@user.telegram_chat_id, at: zone.parse("2026-09-05 10:00"))
    assert_not Telegram::QuietHours.silent?(@user.telegram_chat_id, at: zone.parse("2026-09-05 21:59"))
    assert Telegram::QuietHours.silent?(@user.telegram_chat_id, at: zone.parse("2026-09-05 22:00"))
  end

  # Незнакомый чат (например админский) хозяина не имеет, но будить его ночью
  # тоже незачем — берём пояс по умолчанию, а не падаем.
  test "a chat without an owner falls back to the default timezone" do
    at = ActiveSupport::TimeZone[Telegram::QuietHours::DEFAULT_ZONE].parse("2026-09-05 04:00")

    assert Telegram::QuietHours.silent?(777_000_111, at: at)
  end

  test "a broken timezone does not break the sending" do
    @user.update_column(:timezone, "Mars/Olympus")
    at = ActiveSupport::TimeZone[Telegram::QuietHours::DEFAULT_ZONE].parse("2026-09-05 04:00")

    assert Telegram::QuietHours.silent?(@user.telegram_chat_id, at: at)
  end

  test "the sending API asks telegram for a silent message at night" do
    travel_to Time.utc(2026, 9, 5, 23, 0) do
      assert_equal "true", captured_params { |chat| Telegram::Api.send_simple(chat, "text") }["disable_notification"]
      assert_equal "true", captured_params { |chat| Telegram::Api.send_with_buttons(chat, "text", []) }["disable_notification"]
      assert_equal "true", captured_params { |chat| Telegram::Api.send_api("sendMessage", { chat_id: chat, text: "text" }) }["disable_notification"]
    end
  end

  test "the sending API leaves the sound alone during the day" do
    travel_to Time.utc(2026, 9, 5, 7, 0) do
      assert_nil captured_params { |chat| Telegram::Api.send_simple(chat, "text") }["disable_notification"]
      assert_nil captured_params { |chat| Telegram::Api.send_with_buttons(chat, "text", []) }["disable_notification"]
    end
  end

  # Ответ на нажатие кнопки такого поля не ждёт — лишний параметр там ни к чему.
  test "quiet hours touch only the sending methods" do
    travel_to Time.utc(2026, 9, 5, 23, 0) do
      params = captured_params { Telegram::Api.send_api("answerCallbackQuery", { callback_query_id: "1" }) }

      assert_nil params["disable_notification"]
    end
  end

  # Явное решение вызывающего сильнее часов: закрытие чата молчит и днём.
  test "an explicit choice wins over the clock" do
    travel_to Time.utc(2026, 9, 5, 7, 0) do
      params = captured_params { |chat| Telegram::Api.send_simple(chat, "text", silent: true) }

      assert_equal "true", params["disable_notification"]
    end
  end

  private
    def captured_params
      params = nil
      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent }) do
        yield @user.telegram_chat_id
      end
      params
    end
end
