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
    with_stubbed_singleton_method(TennisLife::TelegramPostsFetcher, :random_post, nil) do
      get tennis_life_index_url
      assert_response :success
    end
  end

  test "index renders without error when random_post is nil" do
    with_stubbed_singleton_method(TennisLife::TelegramPostsFetcher, :random_post, nil) do
      get tennis_life_index_url
      assert_response :success
    end
  end

  test "index shows random telegram post link when present" do
    with_stubbed_singleton_method(TennisLife::TelegramPostsFetcher, :random_post, SAMPLE_POST) do
      get tennis_life_index_url
      assert_response :success
      assert_select "a[href='#{SAMPLE_POST["url"]}']"
    end
  end

  test "index renders telegram widget for random post with valid url" do
    TelegramPost.delete_all
    with_stubbed_singleton_method(TennisLife::TelegramPostsFetcher, :random_post, SAMPLE_POST) do
      get tennis_life_index_url
      assert_response :success
      assert_select "script[data-telegram-post='test/42']"
    end
  end

  private

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
