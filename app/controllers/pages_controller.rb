class PagesController < ApplicationController
  REFERENCE_PAGES = %w[api_and_mcp ntrp_level_guide tennis_formats_and_rules mission].freeze

  # public pages
  skip_before_action :authenticate_user!, only: %i[contacts mission partnership partnership_inquiry tennis_formats_and_rules ntrp_level_guide api_and_mcp privacy_policy more]
  before_action :negotiate_reference_page_format, only: REFERENCE_PAGES

  helper_method :html_to_markdown

  def contacts
  end

  def mission
  end

  def partnership
  end

  def partnership_inquiry
    # honeypot: bots fill hidden fields
    if params[:website].present?
      flash[:notice] = "Thank you! We will get back to you soon."
      redirect_to partnership_path and return
    end

    # rate limit: 3 submissions per IP per hour
    cache_key = "partnership_inquiry:#{request.remote_ip}"
    count = Rails.cache.read(cache_key).to_i
    if count >= 3
      flash[:alert] = "Too many submissions. Please try again later."
      redirect_to partnership_path and return
    end

    name  = params[:name].to_s.strip.first(200)
    org   = params[:organization].to_s.strip.first(200)
    email = params[:email].to_s.strip.first(200)
    msg   = params[:message].to_s.strip.first(1000)

    if name.blank? || email.blank?
      flash[:alert] = "Please fill in your name and email."
      redirect_to partnership_path and return
    end

    text = "Partnership inquiry from #{name}" \
           "#{org.present? ? " (#{org})" : ""}\n" \
           "Email: #{email}\n" \
           "Message: #{msg.presence || '—'}"

    Telegram::AdminNotifier.notify_partnership(text)
    Rails.cache.write(cache_key, count + 1, expires_in: 1.hour)
    flash[:notice] = "Thank you! We will get back to you soon."
    redirect_to partnership_path
  end

  def privacy_policy
  end

  def tennis_formats_and_rules
  end

  def ntrp_level_guide
  end

  # Вкладка «Ещё» в мобильном приложении
  def more
  end

  def api_and_mcp
  end

  private

  def negotiate_reference_page_format
    append_vary_accept

    if params[:format].present?
      case params[:format]
      when "md"
        render_markdown_page
      when "html"
        set_reference_headers(:html)
      else
        head :not_acceptable
      end
      return
    end

    return unless request.get? || request.head?

    case resolve_reference_format(request.headers["Accept"])
    when :md
      render_markdown_page
    when :html
      request.format = :html
      set_reference_headers(:html)
    else
      head :not_acceptable
    end
  end

  def render_markdown_page
    set_reference_headers(:md)
    body = render_to_string(action_name, formats: [ :md ], layout: false)
    render body: CGI.unescapeHTML(body), content_type: "text/markdown; charset=utf-8"
  end

  def append_vary_accept
    vary = response.headers["Vary"]
    if vary.blank?
      response.headers["Vary"] = "Accept"
    elsif !vary.split(",").map(&:strip).include?("Accept")
      response.headers["Vary"] = "#{vary}, Accept"
    end
  end

  def set_reference_headers(format)
    append_vary_accept

    alt_url = if format == :md
      url_for(action: action_name, only_path: false, format: nil)
    else
      url_for(action: action_name, only_path: false, format: :md)
    end
    mime = (format == :md ? "text/html" : "text/markdown")
    response.headers["Link"] = "<#{alt_url}>; rel=\"alternate\"; type=\"#{mime}\""
  end

  def resolve_reference_format(accept_header)
    return :html if accept_header.blank?

    entries = split_header_tokens(accept_header, ",")
    return :html if entries.empty?

    explicit_html_q = nil
    explicit_md_q   = nil
    wildcard_q      = nil
    text_wildcard_q = nil

    entries.each do |entry|
      parts = split_header_tokens(entry, ";")
      next if parts.empty?

      media_type = parts.first.downcase
      params = parts[1..].to_h do |p|
        k, v = p.split("=", 2).map(&:strip)
        [ k.downcase, v ]
      end
      q = params.key?("q") ? Float(params["q"], exception: false) : 1.0
      next if q.nil?

      case media_type
      when "text/html"
        explicit_html_q = q if explicit_html_q.nil? || q > explicit_html_q
      when "text/markdown", "text/x-markdown"
        explicit_md_q = q if explicit_md_q.nil? || q > explicit_md_q
      when "text/*"
        text_wildcard_q = q if text_wildcard_q.nil? || q > text_wildcard_q
      when "*/*"
        wildcard_q = q if wildcard_q.nil? || q > wildcard_q
      end
    end

    effective_html_q = explicit_html_q || text_wildcard_q || wildcard_q || 0.0

    if explicit_md_q && explicit_md_q > 0.0 && explicit_md_q > effective_html_q
      :md
    elsif effective_html_q > 0.0
      :html
    end
  end

  def split_header_tokens(str, delim = ",")
    return [] if str.blank?

    tokens = []
    current = +""
    in_quotes = false
    escaped = false

    str.to_s.each_char do |ch|
      if escaped
        current << ch
        escaped = false
      elsif ch == "\\" && in_quotes
        current << ch
        escaped = true
      elsif ch == '"'
        in_quotes = !in_quotes
        current << ch
      elsif ch == delim && !in_quotes
        stripped = current.strip
        tokens << stripped unless stripped.empty?
        current = +""
      else
        current << ch
      end
    end

    stripped = current.strip
    tokens << stripped unless stripped.empty?
    tokens
  end

  def html_to_markdown(text)
    return "" if text.blank?

    s = text.to_s.dup
    s.gsub!(/<a\s+(?:[^>]*?\s+)?href="([^"]*)"[^>]*>(.*?)<\/a>/im, '[\2](\1)')
    s.gsub!(/<code>(.*?)<\/code>/im, '`\1`')
    s.gsub!(/<(?:strong|b)>(.*?)<\/(?:strong|b)>/im, '**\1**')
    s.gsub!(/<(?:em|i)>(.*?)<\/(?:em|i)>/im, '*\1*')
    s.gsub!(/<br\s*\/?>/i, "\n")
    s.gsub!(/<\/p>/i, "\n\n")
    s.gsub!(/<[^>]+>/, "")
    CGI.unescapeHTML(s).strip
  end
end
