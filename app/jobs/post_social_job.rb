# Одна джоба на все типы постов и все сети. Каждый ранний выход логируем с
# причиной: без этого отладка токенов превращается в гадание.
class PostSocialJob < ApplicationJob
  queue_as :default

  CLAIM_TIMEOUT = 30.minutes

  def perform(kind, dedup_key, network)
    adapter = Social.adapter_for(network)
    return log(kind, dedup_key, network, "unknown network") unless adapter
    return log(kind, dedup_key, network, "adapter not configured") unless adapter.configured?

    content = Social::Content.build(kind, dedup_key)
    return log(kind, dedup_key, network, "no content") unless content
    return log(kind, dedup_key, network, "material is gone") unless content.available?

    claim = claim(kind, dedup_key, network)
    return log(kind, dedup_key, network, "already posted or claimed") unless claim

    begin
      post_id = adapter.new(content: content, locale: Social.locale_for(network)).call
    rescue StandardError
      release(claim)
      raise
    end

    unless post_id
      release(claim)
      return log(kind, dedup_key, network, "adapter returned nothing")
    end

    complete(claim, post_id)
  end

  private

  def claim(kind, dedup_key, network)
    token = "claim:#{SecureRandom.uuid}"
    post = SocialPost.create!(network: network, kind: kind, dedup_key: dedup_key,
                              external_post_id: token, posted_at: nil)
    [ post.id, token ]
  rescue ActiveRecord::RecordNotUnique
    post = SocialPost.find_by!(network: network, kind: kind, dedup_key: dedup_key)
    return if post.posted_at? || post.updated_at >= CLAIM_TIMEOUT.ago

    claimed_at = Time.current
    taken = SocialPost.where(id: post.id, posted_at: nil)
      .where("updated_at < ?", CLAIM_TIMEOUT.ago)
      .update_all(external_post_id: token, updated_at: claimed_at)
    [ post.id, token ] if taken == 1
  end

  def release(claim)
    id, token = claim
    SocialPost.where(id: id, external_post_id: token, posted_at: nil).delete_all
  end

  def complete(claim, post_id)
    id, token = claim
    now = Time.current
    updated = SocialPost.where(id: id, external_post_id: token, posted_at: nil)
      .update_all(external_post_id: post_id, posted_at: now, updated_at: now)
    raise "Social post claim was lost" unless updated == 1
  end

  def log(kind, dedup_key, network, reason)
    Rails.logger.info("[Social] skip #{network} #{kind}/#{dedup_key}: #{reason}")
    nil
  end
end
