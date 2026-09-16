require "test_helper"

class Social::Content::ReleaseTest < ActiveSupport::TestCase
  BODY = <<~MD
    ## Highlights

    Pick a player from a dropdown when logging stats or pre-booking a game.
    Scoreboard times are marked as Moscow time. #GetCourt

    ## What's Changed
    * feat: игрока выбирают в поле с подсказками by @denis1011101 in #197
  MD

  test "posts the highlights section with a version header and the release link" do
    content = build(body: BODY)
    text = content.text(locale: :en)

    assert text.start_with?("🎾 GetCourt v1.4.0 is out\n\n")
    assert_includes text, "Pick a player from a dropdown"
    assert_includes text, "Moscow time. #GetCourt"
    assert_not_includes text, "What's Changed"
    assert_not_includes text, "игрока"
    assert text.end_with?("\n\nhttps://github.com/denis1011101/getcourt/releases/tag/v1.4.0")
    assert_equal "v1.4.0", content.dedup_key
    assert_equal "release", content.kind
  end

  test "carries a clickable link" do
    facets = Social::RichText.facets(build(body: BODY).text(locale: :en))

    assert(facets.any? { |facet| facet["features"].first["$type"].end_with?("#link") })
  end

  test "highlights at the limit still fit the tightest limit we have — 300 graphemes on Bluesky" do
    highlights = "x" * Social::Content::Release::HIGHLIGHTS_LIMIT
    text = build(body: "## Highlights\n\n#{highlights}\n").text(locale: :en)

    assert_operator Social::RichText.grapheme_length(text), :<=, Social::BlueskyPostingService::TEXT_LIMIT
  end

  test "drops the HTML comment GitHub puts before its own list" do
    body = "## Highlights\n\nShort and sweet.\n\n<!-- Release notes generated using configuration in .github/release.yml at v1.4.0 -->\n\n## What's Changed\n* x"

    assert_equal "Short and sweet.", build(body: body).highlights
  end

  test "keeps the link whole and cuts the highlights when the limit is tight" do
    content = build(body: "## Highlights\n\n#{'word ' * 100}")
    text = content.text(locale: :en, limit: Social::BlueskyPostingService::TEXT_LIMIT)

    assert_operator Social::RichText.grapheme_length(text), :<=, Social::BlueskyPostingService::TEXT_LIMIT
    assert text.end_with?("\n\nhttps://github.com/denis1011101/getcourt/releases/tag/v1.4.0")
    assert_includes text, "…"
  end

  test "survives CRLF bodies and a heading in another case" do
    content = build(body: "## highlights\r\n\r\nFirst line\r\nSecond line\r\n\r\n## Other\r\nnope\r\n")

    assert_equal "First line\nSecond line", content.highlights
  end

  test "is unavailable without a Highlights section" do
    content = build(body: "## What's Changed\n* something")

    assert_not content.available?
    assert_match(/no ## Highlights/, content.unavailable_reason)
  end

  test "is unavailable when the section is empty" do
    assert_not build(body: "## Highlights\n\n## What's Changed\n* x").available?
  end

  test "is unavailable for drafts and missing releases" do
    assert_not build(body: BODY, draft: true).available?
    assert_equal "release is still a draft", build(body: BODY, draft: true).unavailable_reason

    missing = Social::Content::Release.new("v9.9.9", release: nil)
    assert_not missing.available?
    assert_equal "no such release on GitHub", missing.unavailable_reason
  end

  test "from_key accepts only vX.Y.Z tags" do
    assert_instance_of Social::Content::Release, Social::Content::Release.from_key("v1.4.0")
    assert_nil Social::Content::Release.from_key("main")
    assert_nil Social::Content::Release.from_key("v1.4")
    assert_nil Social::Content::Release.from_key("1.4.0")
    assert_nil Social::Content::Release.from_key(nil)
  end

  test "Content.build knows the release kind" do
    assert_instance_of Social::Content::Release, Social::Content.build("release", "v1.4.0")
  end

  test "fetch parses a release, treats 404 as missing and raises on anything else" do
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    ok.instance_variable_set(:@read, true)
    ok.instance_variable_set(:@body, { "tag_name" => "v1.4.0", "body" => BODY }.to_json)

    stub_singleton(Net::HTTP, :get_response, ->(*) { ok }) do
      assert_equal "v1.4.0", Social::Content::Release.fetch("v1.4.0")["tag_name"]
    end

    stub_singleton(Net::HTTP, :get_response, ->(*) { Net::HTTPNotFound.new("1.1", "404", "Not Found") }) do
      assert_nil Social::Content::Release.fetch("v1.4.0")
    end

    stub_singleton(Net::HTTP, :get_response, ->(*) { Net::HTTPBadGateway.new("1.1", "502", "Bad Gateway") }) do
      assert_raises(Social::Content::Release::FetchError) { Social::Content::Release.fetch("v1.4.0") }
    end
  end

  test "fetch asks GitHub for the tag of the configured repo" do
    seen = nil
    stub_singleton(Net::HTTP, :get_response, ->(uri, *) { seen = uri; Net::HTTPNotFound.new("1.1", "404", "Not Found") }) do
      Social::Content::Release.fetch("v1.4.0")
    end

    assert_equal "https://api.github.com/repos/denis1011101/getcourt/releases/tags/v1.4.0", seen.to_s
  end

  private

  def build(body:, draft: false)
    Social::Content::Release.new("v1.4.0", release: {
      "tag_name" => "v1.4.0",
      "draft" => draft,
      "html_url" => "https://github.com/denis1011101/getcourt/releases/tag/v1.4.0",
      "body" => body
    })
  end
end
