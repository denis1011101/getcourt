module Social
  module Content
    class Welcome < Base
      # Первый пост в любой новой сети. Держим <= 300 графем — это лимит Bluesky,
      # самый жёсткий из наших площадок; остальные его переживут. Текст лежит в
      # коде, а не в базе: он одинаковый для всех будущих площадок и меняется раз
      # в год. Намеренно не переводится — аккаунты англоязычные.
      TEMPLATE = <<~'POST'.strip
        🎾 Hi! We're GetCourt — a free service for finding tennis, padel,
        table tennis and squash partners.

        📍 Find courts near you
        👥 Join a game or gather your own
        📊 Track matches, scores and your rating

        Looking for a partner today? %{url}

        #GetCourt #tennis #padel #squash
      POST

      def kind
        "welcome"
      end

      def dedup_key
        "getcourt"
      end

      def image_url
        Social.logo_url
      end

      private

      # Ссылку даём со схемой: без неё Bluesky не соберёт link-facet и адрес
      # останется некликабельным текстом.
      def body(locale:)
        format(TEMPLATE, url: Social.app_url)
      end
    end
  end
end
