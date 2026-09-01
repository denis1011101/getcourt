require "test_helper"

class Social::RichTextTest < ActiveSupport::TestCase
  test "counts graphemes, not bytes or codepoints" do
    assert_equal 1, Social::RichText.grapheme_length("🇷🇺")
    assert_equal 3, Social::RichText.grapheme_length("🎾ab")
  end

  test "truncate keeps whole graphemes and marks the cut" do
    assert_equal "abc", Social::RichText.truncate("abc", 5)
    assert_equal "ab…", Social::RichText.truncate("abcdef", 3)
    assert_equal "🎾…", Social::RichText.truncate("🎾🏆🏟", 2)
  end

  test "facet offsets are counted in utf-8 bytes" do
    text = "🎾 tennis https://getcourt.co #GetCourt"
    facets = Social::RichText.facets(text)

    link, tag = facets
    assert_equal "app.bsky.richtext.facet#link", link["features"].first["$type"]
    assert_equal "https://getcourt.co", text.b[link["index"]["byteStart"]...link["index"]["byteEnd"]].force_encoding("UTF-8")

    assert_equal "GetCourt", tag["features"].first["tag"]
    assert_equal "#GetCourt", text.b[tag["index"]["byteStart"]...tag["index"]["byteEnd"]].force_encoding("UTF-8")
  end

  test "trailing punctuation stays out of the link" do
    facets = Social::RichText.facets("see https://getcourt.co/games/1.")

    assert_equal "https://getcourt.co/games/1", facets.first["features"].first["uri"]
  end

  test "a fragment inside a url is not taken for a hashtag" do
    facets = Social::RichText.facets("https://getcourt.co/games/1#top")

    assert_equal 1, facets.size
    assert_equal "app.bsky.richtext.facet#link", facets.first["features"].first["$type"]
  end

  test "a hashtag glued to a word is not a hashtag" do
    assert_empty Social::RichText.facets("nada#tennis")
  end
end
