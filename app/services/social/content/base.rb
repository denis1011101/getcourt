module Social
  module Content
    # Контракт для адаптера: текст + необязательная картинка. Гео и календарь
    # использует только Nostr — остальные площадки их молча игнорируют.
    class Base
      def kind
        raise NotImplementedError
      end

      def dedup_key
        raise NotImplementedError
      end

      # Материал ещё на месте? Проверяется в джобе перед постингом.
      def available?
        true
      end

      def text(locale:, limit: nil)
        RichText.truncate(body(locale: locale), limit)
      end

      def image_url
        nil
      end

      # { lat:, lng:, label: } или nil
      def geo
        nil
      end

      # { title:, starts_at:, ends_at:, location: } или nil — NIP-52
      def calendar
        nil
      end

      private

      def body(locale:)
        raise NotImplementedError
      end
    end
  end
end
