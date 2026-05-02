module ApplicationHelper
  SEO_PRIMARY_HOST = "getcourt.co".freeze
  SEO_INDEXABLE_LOCALES = %w[en ru es].freeze

  def self.host_for_locale(locale)
    locale.to_s == I18n.default_locale.to_s ? SEO_PRIMARY_HOST : "#{locale}.#{SEO_PRIMARY_HOST}"
  end

  def self.canonical_host_for(request)
    subdomain = request.subdomains.first.to_s
    return SEO_PRIMARY_HOST if subdomain.blank? || subdomain == "www" || subdomain == I18n.default_locale.to_s

    SEO_INDEXABLE_LOCALES.include?(subdomain) ? request.host : SEO_PRIMARY_HOST
  end

  TELEGRAM_USERNAME_PATTERN = /(^|[^A-Za-z0-9_])@([A-Za-z0-9_]{5,32})(?=$|[^A-Za-z0-9_])/.freeze

  def pagy_url_for(pagy, page, absolute: false)
    pagy.page_url(page, absolute:)
  end

  def format_date(date)
    date.strftime("%B %d, %Y")
  end

  def format_time(time)
    time.strftime("%I:%M %p")
  end

  def nearby_courts_link
    link_to "Find nearby courts", searches_path, class: "btn btn-primary"
  end

  def telegram_profile_url(username)
    normalized = normalize_telegram_username(username)
    return if normalized.blank?

    "https://t.me/#{normalized}"
  end

  def telegram_profile_link(username, label: nil, **options)
    normalized = normalize_telegram_username(username)
    return unless normalized

    link_to(label || "@#{normalized}", telegram_profile_url(normalized), { target: "_blank", rel: "noopener nofollow" }.merge(options))
  end

  def link_telegram_usernames(text, link_class: nil)
    source = text.to_s
    return "" if source.blank?

    fragments = []
    cursor = 0

    source.to_enum(:scan, TELEGRAM_USERNAME_PATTERN).each do
      match = Regexp.last_match
      username = match[2]
      username_start = match.begin(0) + match[1].length

      fragments << ERB::Util.html_escape(source[cursor...username_start])
      fragments << telegram_profile_link(username, label: "@#{username}", class: link_class)
      cursor = match.end(0)
    end

    fragments << ERB::Util.html_escape(source[cursor..])
    safe_join(fragments.compact)
  end

  # SEO helpers (English defaults). Use content_for(:meta_title)/:meta_description/:meta_image to override per page.
  def meta_title
    (content_for?(:meta_title) && content_for(:meta_title).to_s.presence) ||
      t("meta.default_title")
  end

  def meta_description
    (content_for?(:meta_description) && content_for(:meta_description).to_s.presence) ||
      t("meta.default_description")
  end

  def meta_image
    if content_for?(:meta_image) && content_for(:meta_image).to_s.present?
      content_for(:meta_image).to_s
    else
      "https://#{request.host}/og-image.png"
    end
  end

  def meta_og_type
    (content_for?(:meta_og_type) && content_for(:meta_og_type).to_s.presence) ||
      "website"
  end

  def meta_robots_content
    return content_for(:meta_robots) if content_for?(:meta_robots)

    seo_indexable_locale? ? "index, follow" : "noindex, follow"
  end

  def canonical_url
    return content_for(:canonical_url) if content_for?(:canonical_url)

    "https://#{ApplicationHelper.canonical_host_for(request)}#{request.path}"
  end

  def hreflang_links
    SEO_INDEXABLE_LOCALES.map { |locale| [ locale, localized_url_for(locale) ] } +
      [ [ "x-default", localized_url_for(I18n.default_locale.to_s) ] ]
  end

  private

  def seo_indexable_locale?
    subdomain = request.subdomains.first.to_s
    locale = subdomain.match?(/\A[a-z]{2}\z/) ? subdomain : I18n.default_locale.to_s

    SEO_INDEXABLE_LOCALES.include?(locale)
  end

  def localized_url_for(locale)
    "https://#{ApplicationHelper.host_for_locale(locale)}#{request.path}"
  end

  def absolute_url(path)
    uri = URI(path)
    return path if uri.scheme.present?

    "#{request.protocol}#{request.host_with_port}#{path}"
  end

  def normalize_telegram_username(username)
    candidate = username.to_s.strip.delete_prefix("@")
    return if candidate.blank?
    return unless candidate.match?(/\A[A-Za-z0-9_]{5,32}\z/)

    candidate
  end
end
