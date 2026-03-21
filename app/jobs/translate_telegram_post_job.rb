class TranslateTelegramPostJob < ApplicationJob
  queue_as :default

  def perform(post_id)
    post = TelegramPost.find_by(id: post_id)
    return unless post
    return if post.text_en.present?
    return if post.text.to_s.strip.blank?

    translated = Ai::TranslationService.translate_to_english(post.text)
    post.update_column(:text_en, translated) if translated.present?
  end
end
