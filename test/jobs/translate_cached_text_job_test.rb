require "test_helper"

class TranslateCachedTextJobTest < ActiveJob::TestCase
  test "stores translated text in cache" do
    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { "Hello world" }) do
      TranslateCachedTextJob.new.perform("Привет мир")
    end

    assert_equal "Hello world", TranslationCache.read("Привет мир")
  end

  test "skips translation when fresh cache exists" do
    TranslationCache.create!(
      text_hash: Digest::MD5.hexdigest("Привет"),
      text_en: "Hello"
    )

    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { TranslateCachedTextJob.new.perform("Привет") }
    end
  end
end
