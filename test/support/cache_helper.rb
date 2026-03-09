module CacheHelper
  def with_memory_cache
    cache = ActiveSupport::Cache::MemoryStore.new
    old = Rails.cache
    Rails.cache = cache
    yield
  ensure
    Rails.cache = old
  end
end
