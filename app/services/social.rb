# Внешний кросспостинг. Две независимые оси:
#   контент (что постим)  — Social::Content::*
#   транспорт (куда)      — NETWORKS ниже
# Новая площадка добавляется одной строкой в NETWORKS плюс адаптер с интерфейсом
# `configured?` / `new(content:, locale:).call -> external_post_id | nil`.
module Social
  # Локаль — свойство площадки, а не пользователя: аккаунты во всех трёх сетях
  # англоязычные, поэтому locale в вызове не передаётся, он берётся отсюда.
  NETWORKS = {
    "threads" => { adapter: "Social::ThreadsPostingService", locale: :en },
    "bluesky" => { adapter: "Social::BlueskyPostingService", locale: :en },
    "nostr" => { adapter: "Social::NostrPostingService", locale: :en }
  }.freeze

  class << self
    def adapter_for(network)
      config = NETWORKS[network.to_s]
      config && config[:adapter].constantize
    end

    def locale_for(network)
      config = NETWORKS[network.to_s]
      config ? config[:locale] : I18n.default_locale
    end

    def configured_networks
      NETWORKS.keys.select { |network| adapter_for(network).configured? }
    end

    # Постим во все настроенные сети. Джобе отдаём ключи, а не собранный текст:
    # ActiveJob сериализует аргументы, и к моменту выполнения текст может устареть.
    def publish(content)
      networks = configured_networks
      if networks.empty?
        Rails.logger.info("[Social] skip #{content.kind}/#{content.dedup_key}: no network configured")
        return []
      end

      networks.each { |network| PostSocialJob.perform_later(content.kind, content.dedup_key, network) }
    end

    def publish_urgent(game)
      return [] unless game&.urgent_player_search?

      publish(Content::UrgentSearch.new(game))
    end

    # APP_HOST в проекте встречается и голым хостом, и с протоколом — приводим к
    # одному виду, чтобы ссылки в постах не разъезжались.
    def app_host
      raw = ENV.fetch("APP_HOST", "getcourt.co").to_s.strip
      raw.sub(%r{\Ahttps?://}, "").sub(%r{/+\z}, "")
    end

    def app_url(path = "")
      "https://#{app_host}#{path}"
    end
  end
end
