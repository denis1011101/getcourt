require "test_helper"

class AiChatControllerTest < ActionDispatch::IntegrationTest
  test "returns error for blank message" do
    post ai_chat_path, params: { message: "" }, as: :json
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "required"
  end

  test "returns reply from assistant" do
    fake_service = Object.new
    fake_service.define_singleton_method(:chat) { |_msg, **| "Found 2 opponents in Moscow" }

    stub_singleton(Ai::AssistantService, :new, ->(_user) { fake_service }) do
      post ai_chat_path, params: { message: "Find me an opponent" }, as: :json
      assert_response :success
      assert_equal "Found 2 opponents in Moscow", response.parsed_body["reply"]
    end
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
end
