require "test_helper"

class TennisLifeControllerTest < ActionDispatch::IntegrationTest
  SAMPLE_POST = {
    "channel_name" => "TestChan",
    "channel_url" => "https://t.me/test",
    "text" => "Великий матч!",
    "url" => "https://t.me/test/42",
    "published_at" => "2024-06-01T12:00:00Z"
  }.freeze

  test "should get index" do
    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, nil) do
      get tennis_life_index_url
      assert_response :success
    end
  end

  test "index shows random telegram post link when present" do
    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, SAMPLE_POST) do
      get tennis_life_index_url
      assert_response :success
      assert_select "a[href='#{SAMPLE_POST["url"]}']"
    end
  end

  test "index renders telegram widget for random post with valid url" do
    TelegramPost.delete_all
    stub_singleton(TennisLife::TelegramPostsFetcher, :random_post, SAMPLE_POST) do
      get tennis_life_index_url
      assert_response :success
      assert_select "script[data-telegram-post='test/42']"
    end
  end
end
