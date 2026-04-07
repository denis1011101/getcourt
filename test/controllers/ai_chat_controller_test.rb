require "test_helper"
require "support/cache_helper"

class AiChatControllerTest < ActionDispatch::IntegrationTest
  include CacheHelper

  test "returns error for blank message" do
    post ai_chat_path, params: { message: "" }, as: :json
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "required"
  end

  test "returns reply from assistant" do
    fake_service = Object.new
    calls = []
    fake_service.define_singleton_method(:chat) do |message, **kwargs|
      calls << { message: message, history: kwargs[:history] }
      "Found @tennis_user and @coach_link in Moscow"
    end

    with_memory_cache do
      stub_singleton(Ai::AssistantService, :new, ->(_user) { fake_service }) do
        post ai_chat_path, params: { message: "Find me an opponent" }, as: :json
        assert_response :success
        assert_equal "Found @tennis_user and @coach_link in Moscow", response.parsed_body["reply"]
        assert_includes response.parsed_body["reply_html"], "https://t.me/tennis_user"
        assert_includes response.parsed_body["reply_html"], "https://t.me/coach_link"
      end
    end

    assert_equal [], calls.first[:history]
  end

  test "returns error json when assistant raises" do
    fake_service = Object.new
    fake_service.define_singleton_method(:chat) { |*| raise "boom" }

    stub_singleton(Ai::AssistantService, :new, ->(_user) { fake_service }) do
      post ai_chat_path, params: { message: "hello" }, as: :json
      assert_response :unprocessable_entity
      assert response.parsed_body["error"].present?
    end
  end

  test "passes cached history from previous messages" do
    fake_service = Object.new
    calls = []
    fake_service.define_singleton_method(:chat) do |message, **kwargs|
      calls << { message: message, history: kwargs[:history] }
      "Reply to #{message}"
    end

    with_memory_cache do
      stub_singleton(Ai::AssistantService, :new, ->(_user) { fake_service }) do
        post ai_chat_path, params: { message: "First" }, as: :json
        post ai_chat_path, params: { message: "Second" }, as: :json
      end
    end

    assert_equal [], calls[0][:history]
    assert_equal [
      { role: "user", content: "First" },
      { role: "assistant", content: "Reply to First" }
    ], calls[1][:history]
  end
end
