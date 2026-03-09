require "test_helper"

class TennisLife::TelegramPostsFetcherTest < ActiveSupport::TestCase
  GIST_RESPONSE = {
    "files" => {
      "telegram_posts.json" => {
        "content" => {
          "fetched_at" => "2024-06-01T12:00:00Z",
          "posts" => [
            { "channel_name" => "TestChan", "channel_url" => "https://t.me/test",
              "text" => "Великий матч!", "url" => "https://t.me/test/1",
              "published_at" => "2024-06-01T12:00:00Z" },
            { "channel_name" => "OtherChan", "channel_url" => "https://t.me/other",
              "text" => "Новости тенниса", "url" => "https://t.me/other/7",
              "published_at" => "2024-06-01T11:00:00Z" }
          ]
        }.to_json
      }
    }
  }.freeze

  setup do
    Rails.cache.clear
    ENV["TELEGRAM_POSTS_GIST_ID"] = "abc123"
  end

  teardown do
    Rails.cache.clear
    ENV.delete("TELEGRAM_POSTS_GIST_ID")
  end

  # --- guard: blank config ---

  test "random_post returns nil when TELEGRAM_POSTS_GIST_ID is blank" do
    ENV.delete("TELEGRAM_POSTS_GIST_ID")
    assert_nil TennisLife::TelegramPostsFetcher.random_post
  end

  # --- actual JSON parsing via stubbed fetch_from_api ---

  test "parses posts from gist API response and returns one" do
    with_api_raw(GIST_RESPONSE["files"]["telegram_posts.json"]["content"]) do
      post = TennisLife::TelegramPostsFetcher.random_post
      assert_not_nil post
      assert_includes %w[https://t.me/test/1 https://t.me/other/7], post["url"]
    end
  end

  test "random_post has expected keys from parsed JSON" do
    with_api_raw(GIST_RESPONSE["files"]["telegram_posts.json"]["content"]) do
      post = TennisLife::TelegramPostsFetcher.random_post
      %w[channel_name channel_url text url published_at].each do |key|
        assert post.key?(key), "Expected post to have key '#{key}'"
      end
    end
  end

  test "returns nil when posts array is empty in payload" do
    raw = { "fetched_at" => "2024-06-01T12:00:00Z", "posts" => [] }.to_json
    with_api_raw(raw) do
      assert_nil TennisLife::TelegramPostsFetcher.random_post
    end
  end

  # --- fail-safe ---

  test "returns nil and does not raise when fetch_from_api returns nil (network error)" do
    with_api_raw(nil) do
      assert_nothing_raised { assert_nil TennisLife::TelegramPostsFetcher.random_post }
    end
  end

  test "returns nil and does not raise on malformed JSON" do
    with_api_raw("not valid json {{{") do
      assert_nothing_raised { assert_nil TennisLife::TelegramPostsFetcher.random_post }
    end
  end

  test "returns nil and does not raise when posts key missing from JSON" do
    with_api_raw({ "fetched_at" => "2024-06-01T12:00:00Z" }.to_json) do
      assert_nothing_raised { assert_nil TennisLife::TelegramPostsFetcher.random_post }
    end
  end

  # --- gist response parsing (extract_file_content) ---

  test "extract_file_content returns content for correct filename" do
    body = GIST_RESPONSE
    result = TennisLife::TelegramPostsFetcher.send(:extract_file_content, body)
    assert_equal GIST_RESPONSE["files"]["telegram_posts.json"]["content"], result
  end

  test "extract_file_content raises when file missing from gist" do
    body = { "files" => {} }
    assert_raises(RuntimeError) do
      TennisLife::TelegramPostsFetcher.send(:extract_file_content, body)
    end
  end

  private

  # Stubs private fetch_from_api to return raw string, bypassing HTTP
  # but exercising JSON parsing and all downstream logic in fetch_posts / random_post.
  def with_api_raw(raw, &block)
    Rails.cache.clear
    stub_singleton(TennisLife::TelegramPostsFetcher, :fetch_from_api, ->(*) { raw }, &block)
  end
end
