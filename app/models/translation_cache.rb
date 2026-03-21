class TranslationCache < ApplicationRecord
  # Fetch cached translation or translate and store it.
  # Cleans up entries older than 1 hour on write.
  def self.fetch(text)
    return nil if text.to_s.strip.blank?

    hash = Digest::MD5.hexdigest(text.to_s.strip)
    record = find_by(text_hash: hash)
    return record.text_en if record

    translated = Ai::TranslationService.translate_to_english(text)
    return nil if translated.blank?

    where("created_at < ?", 1.hour.ago).delete_all
    create!(text_hash: hash, text_en: translated)
    translated
  rescue => e
    Rails.logger.error("[TranslationCache] #{e.class}: #{e.message}")
    nil
  end
end
