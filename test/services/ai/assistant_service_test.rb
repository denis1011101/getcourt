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

  test "hydrates short history before asking" do
    user = User.new(email: "assistant@example.test", city_name: "Moscow")

    response = Struct.new(:content).new("done")
    fake_chat = FakeRubyLLMChat.new(response)
    history = [
      { role: "user", content: "Hi" },
      { role: "assistant", content: "Hello" }
    ]

    stub_singleton(RubyLLM, :chat, ->(**) { fake_chat }) do
      Ai::AssistantService.new(user).chat("Find opponent", locale: :en, history: history, timeout_seconds: 1)

      assert_equal history, fake_chat.history_messages
    end
  end

  # Заглушка чата живёт своей жизнью: когда ruby_llm 2.0 убрал with_tool,
  # тесты с ней остались зелёными, а на проде ассистент упал бы на первом
  # сообщении. Держим её честной — каждый её метод должен быть у настоящего чата.
  test "the fake chat only uses methods RubyLLM::Chat really has" do
    fake_methods = FakeRubyLLMChat.public_instance_methods(false) - %i[tools instructions asked_message history_messages]

    fake_methods.each do |name|
      assert RubyLLM::Chat.method_defined?(name), "RubyLLM::Chat больше не умеет #{name}"
    end
  end

  private

  class FakeRubyLLMChat
    attr_reader :tools, :instructions, :asked_message, :history_messages

    def initialize(response)
      @response = response
      @tools = []
      @history_messages = []
    end

    def with_tools(*tools)
      @tools.concat(tools)
      self
    end

    def with_instructions(text)
      @instructions = text
      self
    end

    def add_message(role:, content:)
      @history_messages << { role: role.to_s, content: content }
      self
    end

    def ask(message)
      @asked_message = message
      @response
    end
  end
end
