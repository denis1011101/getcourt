module ApplicationHelper
  def format_date(date)
    date.strftime("%B %d, %Y")
  end

  def format_time(time)
    time.strftime("%I:%M %p")
  end

  def nearby_courts_link
    link_to "Find nearby courts", searches_path, class: "btn btn-primary"
  end

  # SEO helpers (English defaults). Use content_for(:meta_title)/:meta_description/:meta_image to override per page.
  def meta_title
    (content_for?(:meta_title) && content_for(:meta_title).to_s.presence) ||
      "GetCourt — easily create court games and invite friends"
  end

  def meta_description
    (content_for?(:meta_description) && content_for(:meta_description).to_s.presence) ||
      "GetCourt — create events and invite friends for tennis, table tennis, squash and padel. Quick setup, participant management and Telegram reminders."
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
end
