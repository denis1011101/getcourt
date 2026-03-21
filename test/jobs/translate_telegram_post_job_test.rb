require "test_helper"

class TranslateTelegramPostJobTest < ActiveSupport::TestCase
  test "skips if post not found" do
    assert_nothing_raised { TranslateTelegramPostJob.new.perform(0) }
  end

  test "skips if text_en already present" do
    channel = TelegramChannel.create!(username: "@test_ch", url: "https://t.me/test_ch")
    post = TelegramPost.create!(
      telegram_channel: channel,
      message_id: 1,
      text: "Привет",
      text_en: "Hello"
    )

    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { TranslateTelegramPostJob.new.perform(post.id) }
    end
  ensure
    post&.destroy
    channel&.destroy
  end

  test "skips if text is blank" do
    channel = TelegramChannel.create!(username: "@test_ch2", url: "https://t.me/test_ch2")
    post = TelegramPost.create!(telegram_channel: channel, message_id: 2, text: nil)

    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { TranslateTelegramPostJob.new.perform(post.id) }
    end
  ensure
    post&.destroy
    channel&.destroy
  end

  test "translates and saves text_en" do
    channel = TelegramChannel.create!(username: "@test_ch3", url: "https://t.me/test_ch3")
    post = TelegramPost.create!(telegram_channel: channel, message_id: 3, text: "Привет мир")

    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { "Hello world" }) do
      TranslateTelegramPostJob.new.perform(post.id)
    end

    assert_equal "Hello world", post.reload.text_en
  ensure
    post&.destroy
    channel&.destroy
  end
end
