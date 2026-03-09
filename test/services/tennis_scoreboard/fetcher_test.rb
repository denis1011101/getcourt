require "test_helper"

class TennisScoreboard::FetcherTest < ActiveSupport::TestCase
  GIST_RESPONSE = {
    "files" => {
      "sport_events.txt" => {
        "content" => "<b>Теннис</b>\nФедерер — Надаль 6:3 6:4\n<b>Футбол</b>\nРеал — Барса 2:1\n"
      }
    }
  }.freeze

  TENNIS_CONTENT = GIST_RESPONSE["files"]["sport_events.txt"]["content"]

  setup do
    Rails.cache.clear
    ENV["TENNIS_SCORE_GIST_URL"] = "https://gist.github.com/user/abc1234567890abcdef"
  end

  teardown do
    Rails.cache.clear
    ENV.delete("TENNIS_SCORE_GIST_URL")
    ENV.delete("TENNIS_SCORE_GIST_TOKEN")
  end

  # --- guard: blank / invalid config ---

  test "raw_text returns nil when TENNIS_SCORE_GIST_URL is blank" do
    ENV.delete("TENNIS_SCORE_GIST_URL")
    assert_nil TennisScoreboard::Fetcher.raw_text
  end

  test "raw_text returns nil and warns when URL has no gist id" do
    ENV["TENNIS_SCORE_GIST_URL"] = "https://example.com/not-a-gist"
    assert_nothing_raised { assert_nil TennisScoreboard::Fetcher.raw_text }
  end

  test "raw_text works with raw gist.githubusercontent.com URL (production URL shape)" do
    ENV["TENNIS_SCORE_GIST_URL"] =
      "https://gist.githubusercontent.com/user/abc1234567890abcdef/raw/rev/sport_events.txt"
    with_api_response(GIST_RESPONSE) do
      assert_equal TENNIS_CONTENT, TennisScoreboard::Fetcher.raw_text
    end
  end

  # --- successful API fetch ---

  test "raw_text returns first file content from gist API response" do
    with_api_response(GIST_RESPONSE) do
      assert_equal TENNIS_CONTENT, TennisScoreboard::Fetcher.raw_text
    end
  end

  test "raw_text picks first file regardless of filename" do
    response = { "files" => { "other_name.txt" => { "content" => "some text" } } }
    with_api_response(response) do
      assert_equal "some text", TennisScoreboard::Fetcher.raw_text
    end
  end

  # --- fail-safe ---

  test "raw_text returns nil and does not raise when fetch_from_api returns nil" do
    with_api_response(nil) do
      assert_nothing_raised { assert_nil TennisScoreboard::Fetcher.raw_text }
    end
  end

  test "raw_text returns nil and does not raise when gist has no files" do
    with_api_response({ "files" => {} }) do
      assert_nothing_raised { assert_nil TennisScoreboard::Fetcher.raw_text }
    end
  end

  # --- extract_gist_id ---

  test "extract_gist_id parses standard gist URL" do
    id = TennisScoreboard::Fetcher.send(:extract_gist_id,
      "https://gist.github.com/user/abc1234567890abcdef")
    assert_equal "abc1234567890abcdef", id
  end

  test "extract_gist_id parses raw gist.githubusercontent.com URL" do
    id = TennisScoreboard::Fetcher.send(:extract_gist_id,
      "https://gist.githubusercontent.com/user/abc1234567890abcdef/raw/rev/sport_events.txt")
    assert_equal "abc1234567890abcdef", id
  end

  test "extract_gist_id returns nil for non-gist URL" do
    id = TennisScoreboard::Fetcher.send(:extract_gist_id, "https://example.com/foo")
    assert_nil id
  end

  # --- extract_file_content ---

  test "extract_file_content returns content of first file" do
    result = TennisScoreboard::Fetcher.send(:extract_file_content, GIST_RESPONSE)
    assert_equal TENNIS_CONTENT, result
  end

  test "extract_file_content raises when files is empty" do
    assert_raises(RuntimeError) do
      TennisScoreboard::Fetcher.send(:extract_file_content, { "files" => {} })
    end
  end

  private

  def with_api_response(gist_body, &block)
    Rails.cache.clear
    raw = gist_body.nil? ? nil : gist_body.dig("files")&.values&.first&.dig("content")
    with_stubbed_singleton_method(TennisScoreboard::Fetcher, :fetch_from_api, ->(*) { raw }, &block)
  end

  def with_stubbed_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    had_method = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
    original = singleton.instance_method(method_name) if had_method
    callable = replacement.respond_to?(:call) ? replacement : ->(*) { replacement }
    singleton.define_method(method_name) { |*args, **kwargs, &blk| callable.call(*args, **kwargs, &blk) }
    yield
  ensure
    had_method ? singleton.define_method(method_name, original) : singleton.remove_method(method_name)
  end
end
