require "test_helper"
require "support/cache_helper"

class Telegram::Flows::AiAssistantFlowTest < ActiveSupport::TestCase
  include CacheHelper

  test "back callback finishes conversation and shows menu" do
    with_memory_cache do
      Telegram::Helpers::Conversation.start("123", "flow" => "ai_assistant")
      callback = { "id" => "cb1", "data" => "ai:back", "message" => { "message_id" => 77, "chat" => { "id" => "123" } } }
      menu_called = false

      stub_singleton(Telegram::Api, :answer_callback, ->(*) { true }) do
        stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(chat_id, message_id:) {
          menu_called = true
          assert_equal "123", chat_id
          assert_equal 77, message_id
        }) do
          assert Telegram::Flows::AiAssistantFlow.handle_callback(callback)
        end
      end

      assert menu_called
      assert_equal({}, Telegram::Helpers::Conversation.get("123"))
    end
  end

  test "slash command exits ai flow and lets command routing continue" do
    with_memory_cache do
      Telegram::Helpers::Conversation.start("321", "flow" => "ai_assistant")
      message = { "chat" => { "id" => "321" }, "text" => "/menu" }

      assert_equal false, Telegram::Flows::AiAssistantFlow.process_text(message)
      assert_equal({}, Telegram::Helpers::Conversation.get("321"))
    end
  end

  test "respond edits thinking message and chunks long answers" do
    with_memory_cache do
      user = User.new(email: "ai-flow@example.test", telegram_chat_id: "654")
      Telegram::Helpers::Conversation.start("654", "flow" => "ai_assistant")
      long_answer = "A" * 5000
      edits = []
      sends = []

      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :en) do
        stub_singleton(Telegram::Helpers::UserLookup, :find_user, user) do
          stub_singleton(Ai::AssistantService, :new, FakeAssistantServiceFactory.new(long_answer)) do
            stub_singleton(Telegram::Api, :send_simple, ->(*args, **kwargs) {
              sends << [ args, kwargs ]
              { "result" => { "message_id" => 42 } }
            }) do
              stub_singleton(Telegram::Api, :edit_message_text, ->(*args, **kwargs) {
                edits << [ args, kwargs ]
                true
              }) do
                assert Telegram::Flows::AiAssistantFlow.process_text({ "chat" => { "id" => "654" }, "text" => "find opponent" })
              end
            end
          end
        end
      end

      assert_equal "Thinking...", sends[0][0][1]
      assert_equal 42, edits[0][0][1]
      assert_operator edits[0][0][2].length, :<=, 4096
      assert_equal 2, sends.size
      assert_operator sends[1][0][1].length, :<=, 4096
    end
  end

  test "timeout edits thinking message with localized fallback" do
    with_memory_cache do
      user = User.new(email: "ai-timeout@example.test", telegram_chat_id: "655")
      Telegram::Helpers::Conversation.start("655", "flow" => "ai_assistant")
      edits = []
      sends = []

      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :en) do
        stub_singleton(Telegram::Helpers::UserLookup, :find_user, user) do
          stub_singleton(Ai::AssistantService, :new, FakeAssistantServiceFactory.new(-> { raise Timeout::Error, "expired" })) do
            stub_singleton(Telegram::Api, :send_simple, ->(*args, **kwargs) {
              sends << [ args, kwargs ]
              { "result" => { "message_id" => 43 } }
            }) do
              stub_singleton(Telegram::Api, :edit_message_text, ->(*args, **kwargs) {
                edits << [ args, kwargs ]
                true
              }) do
                assert Telegram::Flows::AiAssistantFlow.process_text({ "chat" => { "id" => "655" }, "text" => "find court" })
              end
            end
          end
        end
      end

      assert_equal "Thinking...", sends[0][0][1]
      assert_equal Telegram::I18n.t(:ai_timeout, locale: :en), edits[0][0][2]
      assert_equal 1, sends.size
    end
  end

  private

  class FakeAssistantServiceFactory
    def initialize(answer_or_callable)
      @answer_or_callable = answer_or_callable
    end

    def call(*)
      FakeAssistantService.new(@answer_or_callable)
    end
    alias_method :new, :call
  end

  class FakeAssistantService
    def initialize(answer_or_callable)
      @answer_or_callable = answer_or_callable
    end

    def chat(*, **)
      return @answer_or_callable.call if @answer_or_callable.respond_to?(:call)

      @answer_or_callable
    end
  end
end
