class TranslationCache < ApplicationRecord
  TTL = 1.hour

  # Fetch cached translation or translate and store it.
  # Cleans up entries older than 1 hour on write.
  def self.read(text)
    normalized = normalize_text(text)
    return nil unless normalized

    fresh_record_for(normalized)&.text_en
  rescue => e
    Rails.logger.error("[TranslationCache] #{e.class}: #{e.message}")
    nil
  end

  def self.fetch(text)
    normalized = normalize_text(text)
    return nil unless normalized

    cached = fresh_record_for(normalized)
    return cached.text_en if cached

    translated = Ai::TranslationService.translate_to_english(normalized)
    store(normalized, translated)
  rescue => e
    Rails.logger.error("[TranslationCache] #{e.class}: #{e.message}")
    nil
  end

  def self.enqueue(text)
    normalized = normalize_text(text)
    return if normalized.blank?
    return if read(normalized).present?

    TranslateCachedTextJob.perform_later(normalized)
  rescue => e
    Rails.logger.error("[TranslationCache] #{e.class}: #{e.message}")
    nil
  end

  def self.prune_expired!
    where("created_at < ?", TTL.ago).delete_all
  end

  private_class_method def self.normalize_text(text)
    text.to_s.strip.presence
  end

  private_class_method def self.text_hash_for(text)
    Digest::MD5.hexdigest(text)
  end

  private_class_method def self.fresh_record_for(text)
    record = find_by(text_hash: text_hash_for(text))
    return unless record

    if record.created_at < TTL.ago
      record.destroy!
      return
    end

    record
  end

  private_class_method def self.store(text, translated)
    return nil if translated.blank?

    prune_expired!
    where(text_hash: text_hash_for(text)).delete_all
    create!(text_hash: text_hash_for(text), text_en: translated)
    translated
  rescue ActiveRecord::RecordNotUnique
    find_by(text_hash: text_hash_for(text))&.text_en || translated
  end
end
