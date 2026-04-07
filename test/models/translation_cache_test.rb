require "test_helper"

class TranslationCacheTest < ActiveSupport::TestCase
  test "returns nil for blank text" do
    assert_nil TranslationCache.read("")
    assert_nil TranslationCache.fetch("")
    assert_nil TranslationCache.fetch(nil)
    assert_nil TranslationCache.fetch("   ")
  end

  test "translates and stores on first call" do
    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { "Hello world" }) do
      result = TranslationCache.fetch("Привет мир")
      assert_equal "Hello world", result
      assert TranslationCache.find_by(text_hash: Digest::MD5.hexdigest("Привет мир"))
    end
  end

  test "returns cached value without calling translation service again" do
    TranslationCache.create!(
      text_hash: Digest::MD5.hexdigest("Привет"),
      text_en: "Hello"
    )

    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { raise "should not be called" }) do
      assert_equal "Hello", TranslationCache.read("Привет")
      assert_equal "Hello", TranslationCache.fetch("Привет")
    end
  end

  test "read ignores stale cached value older than 1 hour" do
    record = TranslationCache.create!(
      text_hash: Digest::MD5.hexdigest("Привет"),
      text_en: "Hello"
    )
    record.update_column(:created_at, 2.hours.ago)

    assert_nil TranslationCache.read("Привет")
    assert_nil TranslationCache.find_by(id: record.id)
  end

  test "returns nil when translation service returns blank" do
    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { nil }) do
      assert_nil TranslationCache.fetch("Привет")
      assert_nil TranslationCache.find_by(text_hash: Digest::MD5.hexdigest("Привет"))
    end
  end

  test "deletes entries older than 1 hour on write" do
    old = TranslationCache.create!(
      text_hash: Digest::MD5.hexdigest("old text"),
      text_en: "old translation"
    )
    old.update_column(:created_at, 2.hours.ago)

    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { "New translation" }) do
      TranslationCache.fetch("new text")
    end

    assert_nil TranslationCache.find_by(id: old.id)
  end

  test "enqueue schedules background translation only when cache is missing" do
    previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    TranslationCache.enqueue("Привет")

    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.count
    assert_equal "TranslateCachedTextJob", ActiveJob::Base.queue_adapter.enqueued_jobs.last[:job].to_s
  ensure
    ActiveJob::Base.queue_adapter = previous_queue_adapter
  end

  test "enqueue skips background translation when fresh cache exists" do
    previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    TranslationCache.create!(
      text_hash: Digest::MD5.hexdigest("Привет"),
      text_en: "Hello"
    )

    TranslationCache.enqueue("Привет")

    assert_equal 0, ActiveJob::Base.queue_adapter.enqueued_jobs.count
  ensure
    ActiveJob::Base.queue_adapter = previous_queue_adapter
  end

  test "returns nil and logs on error" do
    stub_singleton(Ai::TranslationService, :translate_to_english, ->(_) { raise "boom" }) do
      assert_nil TranslationCache.fetch("Привет")
    end
  end
end
