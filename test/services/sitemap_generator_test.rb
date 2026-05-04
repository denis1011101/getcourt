require "test_helper"
require "nokogiri"

class SitemapGeneratorTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  NS = {
    "sitemap" => "http://www.sitemaps.org/schemas/sitemap/0.9",
    "xhtml" => "http://www.w3.org/1999/xhtml"
  }.freeze

  setup do
    @sitemap_file = Rails.root.join("public", "sitemap.xml")
    @previous_sitemap = File.exist?(@sitemap_file) ? File.read(@sitemap_file) : nil
  end

  teardown do
    if @previous_sitemap
      File.write(@sitemap_file, @previous_sitemap)
    elsif File.exist?(@sitemap_file)
      File.delete(@sitemap_file)
    end
  end

  test "generates multilingual sitemap with hreflang alternates" do
    SitemapGenerator.generate!
    document = Nokogiri::XML(File.read(@sitemap_file))

    assert_empty document.errors
    assert_includes locs(document), "https://getcourt.co/"
    assert_includes locs(document), "https://ru.getcourt.co/"
    assert_includes locs(document), "https://es.getcourt.co/"

    url_nodes(document).each do |url_node|
      assert_hreflang_links(url_node)
    end
  end

  test "dynamic records include localized urls alternates and lastmod" do
    match = FeaturedMatch.create!(
      tournament_label: "Madrid Open Final",
      player_left_name: "J. Sinner",
      player_right_name: "A. Zverev",
      starts_at: 1.day.from_now
    )

    SitemapGenerator.generate!
    document = Nokogiri::XML(File.read(@sitemap_file))

    assert_dynamic_record(document, courts(:one), court_path(courts(:one)))
    assert_dynamic_record(document, games(:one), game_path(games(:one)))
    assert_dynamic_record(document, match, event_path(match))
  end

  private

  def locs(document)
    document.xpath("//sitemap:url/sitemap:loc", NS).map(&:text)
  end

  def url_nodes(document)
    document.xpath("//sitemap:url", NS)
  end

  def assert_dynamic_record(document, record, path)
    ApplicationHelper::SEO_INDEXABLE_LOCALES.each do |locale|
      url_node = find_url(document, localized_url(locale, path))

      assert url_node, "Expected #{localized_url(locale, path)} in sitemap"
      assert_equal record.updated_at.to_date.iso8601, url_node.at_xpath("sitemap:lastmod", NS).text
      assert_hreflang_links(url_node)
    end
  end

  def assert_hreflang_links(url_node)
    links = url_node.xpath("xhtml:link", NS)

    assert_equal 4, links.size
    assert_equal %w[en ru es x-default], links.map { |link| link["hreflang"] }

    default_link = links.find { |link| link["hreflang"] == "x-default" }
    assert_match %r{\Ahttps://getcourt\.co/}, default_link["href"]
    assert_no_match %r{\Ahttps://(?:ru|es)\.getcourt\.co/}, default_link["href"]
  end

  def find_url(document, loc)
    url_nodes(document).find do |url_node|
      url_node.at_xpath("sitemap:loc", NS).text == loc
    end
  end

  def localized_url(locale, path)
    "https://#{ApplicationHelper.host_for_locale(locale)}#{path}"
  end
end
