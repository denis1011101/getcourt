require "test_helper"

class NotifyPrebookingOwnerJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "uses email when owner selected email notifications" do
    game = games(:one)
    requester = users(:two)
    owner = game.user
    owner.update_columns(email: "prebooking-owner@example.com", locale: "en", notification_channel: "email")
    prebooking = game.prebookings.create!(date: Date.current + 7.days, slot_index: 99, user: requester, status: "pending")
    batch_ts = "email-batch"

    with_cache_value("prebooking_notify:#{game.id}:#{requester.id}", batch_ts) do
      assert_enqueued_emails 1 do
        NotifyPrebookingOwnerJob.perform_now(game.id, requester.id, batch_ts)
      end
    end
  ensure
    prebooking&.destroy
  end

  test "keeps interactive buttons when owner selected telegram" do
    game = games(:one)
    requester = users(:two)
    owner = game.user
    owner.update_columns(telegram_chat_id: 67_890, telegram_locale: "en", notification_channel: "telegram")
    prebooking = game.prebookings.create!(date: Date.current + 8.days, slot_index: 98, user: requester, status: "pending")
    batch_ts = "telegram-batch"
    sent = nil

    with_cache_value("prebooking_notify:#{game.id}:#{requester.id}", batch_ts) do
      stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { sent = args }) do
        NotifyPrebookingOwnerJob.perform_now(game.id, requester.id, batch_ts)
      end
    end

    assert_equal owner.telegram_chat_id, sent.first
    assert_equal "game:approve_all_prebookings:#{game.id}:#{requester.id}", sent.third.first.first[:callback_data]
  ensure
    prebooking&.destroy
  end

  private

  def with_cache_value(key, value)
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write(key, value)
    original = Rails.cache
    Rails.cache = cache
    yield
  ensure
    Rails.cache = original
  end
end
