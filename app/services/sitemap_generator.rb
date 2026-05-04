class SitemapGenerator
  include Rails.application.routes.url_helpers

  def self.generate!
    new.generate!
  end

  def generate!
    xml = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    xml << "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">\n"

    sitemap_paths.each do |path, lastmod|
      alternates = localized_alternates(path)
      x_default = absolute_url_for_locale(I18n.default_locale, path)

      ApplicationHelper::SEO_INDEXABLE_LOCALES.each do |locale|
        add_url(xml, absolute_url_for_locale(locale, path), lastmod, alternates: alternates, x_default: x_default)
      end
    end

    xml << "</urlset>\n"

    file = Rails.root.join("public", "sitemap.xml")
    File.write(file, xml)
    Rails.logger.info "Sitemap generated: #{file}"
    file.to_s
  end

  private

  def sitemap_paths
    static_paths + dynamic_paths
  end

  def static_paths
    [
      [ root_path, nil ],
      [ courts_path, nil ],
      [ tennis_life_path, nil ],
      [ contacts_path, nil ],
      [ mission_path, nil ],
      [ partnership_path, nil ],
      [ tennis_formats_and_rules_path, nil ],
      [ ntrp_level_guide_path, nil ]
    ]
  end

  def dynamic_paths
    court_paths + game_paths + event_paths
  end

  def court_paths
    Court.find_each.map { |court| [ court_path(court), court.updated_at ] }
  end

  def game_paths
    Game.find_each.map { |game| [ game_path(game), game.updated_at ] }
  end

  def event_paths
    FeaturedMatch.where.not(slug: nil).find_each.map { |match| [ event_path(match), match.updated_at ] }
  end

  def localized_alternates(path)
    ApplicationHelper::SEO_INDEXABLE_LOCALES.map do |locale|
      [ locale, absolute_url_for_locale(locale, path) ]
    end
  end

  def absolute_url_for_locale(locale, path)
    "https://#{ApplicationHelper.host_for_locale(locale)}#{path}"
  end

  def add_url(xml, loc, lastmod = nil, alternates: [], x_default: nil)
    xml << "  <url>\n"
    xml << "    <loc>#{CGI.escapeHTML(loc)}</loc>\n"
    xml << "    <lastmod>#{lastmod.to_date.iso8601}</lastmod>\n" if lastmod
    alternates.each do |locale, href|
      xml << "    <xhtml:link rel=\"alternate\" hreflang=\"#{CGI.escapeHTML(locale)}\" href=\"#{CGI.escapeHTML(href)}\" />\n"
    end
    xml << "    <xhtml:link rel=\"alternate\" hreflang=\"x-default\" href=\"#{CGI.escapeHTML(x_default)}\" />\n" if x_default
    xml << "  </url>\n"
  end
end
