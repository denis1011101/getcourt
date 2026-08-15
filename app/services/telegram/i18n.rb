module Telegram
  module I18n
    LOCALES = %w[ru en es].freeze
    DEFAULT_LOCALE = "ru".freeze

    def self.locale_for(user)
      return DEFAULT_LOCALE unless user

      locale = user.respond_to?(:telegram_locale) ? user.telegram_locale.to_s.strip : ""
      LOCALES.include?(locale) ? locale : DEFAULT_LOCALE
    end

    def self.t(key, locale: DEFAULT_LOCALE, **args)
      locale = normalize_locale(locale)
      translation_key = "telegram.#{key}"
      translation_locale = ::I18n.exists?(translation_key, locale) ? locale : "en"

      unless ::I18n.exists?(translation_key, translation_locale)
        Rails.logger.warn("[Telegram::I18n] missing key #{translation_key} (locale=#{locale})")
        return key.to_s
      end

      begin
        ::I18n.t(translation_key, locale: translation_locale, **args)
      rescue ::I18n::MissingInterpolationArgument => e
        # A missing argument in some rare branch must not take the poller down:
        # log it and let the raw %{...} through, the way the old gsub did. Retrying
        # without any values is what does that: I18n only interpolates when values
        # are given, so the template comes back untouched.
        Rails.logger.warn("[Telegram::I18n] #{translation_key} (locale=#{translation_locale}): #{e.message}")
        ::I18n.t(translation_key, locale: translation_locale, default: key.to_s)
      end
    end

    def self.for_user(user)
      locale_for(user)
    end

    def self.locale_from_language_code(language_code)
      locale = language_code.to_s.split("-").first.downcase
      locale if LOCALES.include?(locale)
    end

    def self.spots_left_text(count, locale: DEFAULT_LOCALE)
      key = case locale.to_s
      when "ru"
        n = count.abs % 100
        n1 = n % 10
        if n > 10 && n < 20
          :spots_left
        elsif n1 > 1 && n1 < 5
          :spots_left_few
        elsif n1 == 1
          :spot_left
        else
          :spots_left
        end
      else
        count == 1 ? :spot_left : :spots_left
      end

      t(key, locale: locale, count: count)
    end

    def self.normalize_locale(locale)
      locale = locale.to_s
      LOCALES.include?(locale) ? locale : DEFAULT_LOCALE
    end
    private_class_method :normalize_locale
  end
end
