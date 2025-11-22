class SitemapGenerator
  include Rails.application.routes.url_helpers

  DEFAULT_HOST = ENV.fetch("HOSTNAME") { ENV.fetch("APP_HOST", "https://getcourt.co") }

  def self.generate!
    new.generate!
  end

  def initialize(host: DEFAULT_HOST)
    @host = host.chomp("/")
    Rails.application.routes.default_url_options[:host] = URI(@host).host
    Rails.application.routes.default_url_options[:protocol] = URI(@host).scheme || "https"
  end

  def generate!
    xml = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    xml << "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"

    add_url(xml, root_url)
    Court.find_each do |court|
      add_url(xml, court_url(court), court.updated_at)
    end

    Game.find_each do |game|
      add_url(xml, game_url(game), game.updated_at)
    end

    xml << "</urlset>\n"

    file = Rails.root.join("public", "sitemap.xml")
    File.write(file, xml)
    Rails.logger.info "Sitemap generated: #{file}"
    file.to_s
  end

  private

  def root_url
    "#{@host}/"
  end

  def court_url(court)
    "#{@host}#{Rails.application.routes.url_helpers.court_path(court)}"
  end

  def game_url(game)
    "#{@host}#{Rails.application.routes.url_helpers.game_path(game)}"
  end

  def add_url(xml, loc, lastmod = nil)
    xml << "  <url>\n"
    xml << "    <loc>#{CGI.escapeHTML(loc)}</loc>\n"
    xml << "    <lastmod>#{lastmod.to_date.iso8601}</lastmod>\n" if lastmod
    xml << "  </url>\n"
  end
end
