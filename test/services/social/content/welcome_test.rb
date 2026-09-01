require "test_helper"

class Social::Content::WelcomeTest < ActiveSupport::TestCase
  test "fits into the tightest limit we have — 300 graphemes on Bluesky" do
    text = Social::Content::Welcome.new.text(locale: :en)

    assert_operator Social::RichText.grapheme_length(text), :<=, Social::BlueskyPostingService::TEXT_LIMIT
  end

  test "carries a clickable link and a stable dedup key" do
    content = Social::Content::Welcome.new
    facets = Social::RichText.facets(content.text(locale: :en))

    assert_equal "getcourt", content.dedup_key
    assert(facets.any? { |facet| facet["features"].first["$type"].end_with?("#link") })
  end
end
