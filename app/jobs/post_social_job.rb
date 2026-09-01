# Одна джоба на все типы постов и все сети. Каждый ранний выход логируем с
# причиной: без этого отладка токенов превращается в гадание.
class PostSocialJob < ApplicationJob
  queue_as :default

  def perform(kind, dedup_key, network)
    adapter = Social.adapter_for(network)
    return log(kind, dedup_key, network, "unknown network") unless adapter
    return log(kind, dedup_key, network, "adapter not configured") unless adapter.configured?
    return log(kind, dedup_key, network, "already posted") if already_posted?(kind, dedup_key, network)

    content = Social::Content.build(kind, dedup_key)
    return log(kind, dedup_key, network, "no content") unless content
    return log(kind, dedup_key, network, "material is gone") unless content.available?

    post_id = adapter.new(content: content, locale: Social.locale_for(network)).call
    return log(kind, dedup_key, network, "adapter returned nothing") unless post_id

    record(kind, dedup_key, network, post_id)
  end

  private

  def already_posted?(kind, dedup_key, network)
    SocialPost.exists?(network: network, kind: kind, dedup_key: dedup_key)
  end

  def record(kind, dedup_key, network, post_id)
    SocialPost.create!(
      network: network, kind: kind, dedup_key: dedup_key,
      external_post_id: post_id, posted_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    # Две джобы на один материал разошлись по времени — пост уже записан.
    log(kind, dedup_key, network, "duplicate record")
  end

  def log(kind, dedup_key, network, reason)
    Rails.logger.info("[Social] skip #{network} #{kind}/#{dedup_key}: #{reason}")
    nil
  end
end
