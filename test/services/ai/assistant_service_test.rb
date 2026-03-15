require "test_helper"

class Ai::AssistantServiceTest < ActiveSupport::TestCase
  test "builds chat with tools and localized instructions" do
    user = User.new(email: "assistant@example.test", city_name: "Moscow")

    response = Struct.new(:content).new("done")
    fake_chat = FakeRubyLLMChat.new(response)

    stub_singleton(RubyLLM, :chat, ->(**kwargs) {
      assert_equal "gemini-2.5-flash", kwargs[:model]
      fake_chat
    }) do
      result = Ai::AssistantService.new(user).chat("Find opponent", locale: :en, timeout_seconds: 1)

      assert_equal "done", result
      assert_instance_of Ai::Tools::FindOpponentTool, fake_chat.tools[0]
      assert_instance_of Ai::Tools::FindCourtTool, fake_chat.tools[1]
      assert_includes fake_chat.instructions, "Respond in the user's language (en)."
      assert_equal "Find opponent", fake_chat.asked_message
    end
  end

  private

  class FakeRubyLLMChat
    attr_reader :tools, :instructions, :asked_message

    def initialize(response)
      @response = response
      @tools = []
    end

    def with_tool(tool)
      @tools << tool
      self
    end

    def with_instructions(text)
      @instructions = text
      self
    end

    def ask(message)
      @asked_message = message
      @response
    end
  end
end
