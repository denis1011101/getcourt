module ApplicationHelper
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
      "GetCourt — easily create games and invite friends"
  end

  def meta_description
    (content_for?(:meta_description) && content_for(:meta_description).to_s.presence) ||
      "GetCourt — create games and invite friends for tennis, table tennis, squash and padel. Quick setup, participant management and Telegram reminders."
  end

  def meta_image
    if content_for?(:meta_image) && content_for(:meta_image).to_s.present?
      content_for(:meta_image).to_s
    else
      # keep a fallback in public/ (add public/og-image.png) or use absolute URL
      absolute_url(asset_path("og-image.png")) rescue "https://getcourt.co/og-image.png"
    end
  end

  private

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
