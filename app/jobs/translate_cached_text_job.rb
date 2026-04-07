class TranslateCachedTextJob < ApplicationJob
  queue_as :default

  def perform(text)
    TranslationCache.fetch(text)
  end
end
