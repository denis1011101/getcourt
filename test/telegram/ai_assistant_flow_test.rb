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
      calls = []

      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :en) do
        stub_singleton(Telegram::Helpers::UserLookup, :find_user, user) do
          stub_singleton(Ai::AssistantService, :new, FakeAssistantServiceFactory.new(long_answer, calls)) do
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
      assert_equal [], calls[0][:history]
      assert_equal [
        { role: "user", content: "find opponent" },
        { role: "assistant", content: long_answer }
      ], Ai::ChatContextStore.fetch(channel: :telegram, key: "654")
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

  test "service unavailable edits thinking message with localized fallback" do
    with_memory_cache do
      user = User.new(email: "ai-unavailable@example.test", telegram_chat_id: "657")
      Telegram::Helpers::Conversation.start("657", "flow" => "ai_assistant")
      edits = []
      sends = []

      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :ru) do
        stub_singleton(Telegram::Helpers::UserLookup, :find_user, user) do
          stub_singleton(Ai::AssistantService, :new, FakeAssistantServiceFactory.new(-> { raise RubyLLM::ServiceUnavailableError, "busy" })) do
            stub_singleton(Telegram::Api, :send_simple, ->(*args, **kwargs) {
              sends << [ args, kwargs ]
              { "result" => { "message_id" => 45 } }
            }) do
              stub_singleton(Telegram::Api, :edit_message_text, ->(*args, **kwargs) {
                edits << [ args, kwargs ]
                true
              }) do
                assert Telegram::Flows::AiAssistantFlow.process_text({ "chat" => { "id" => "657" }, "text" => "find coach" })
              end
            end
          end
        end
      end

      assert_equal "Думаю...", sends[0][0][1]
      assert_equal Telegram::I18n.t(:ai_service_unavailable, locale: :ru), edits[0][0][2]
      assert_equal 1, sends.size
    end
  end

  test "respond passes cached history from previous telegram messages" do
    with_memory_cache do
      user = User.new(email: "ai-history@example.test", telegram_chat_id: "656")
      Telegram::Helpers::Conversation.start("656", "flow" => "ai_assistant")
      sends = []
      calls = []

      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :en) do
        stub_singleton(Telegram::Helpers::UserLookup, :find_user, user) do
          stub_singleton(Ai::AssistantService, :new, FakeAssistantServiceFactory.new(-> { "ok" }, calls)) do
            stub_singleton(Telegram::Api, :send_simple, ->(*args, **kwargs) {
              sends << [ args, kwargs ]
              { "result" => { "message_id" => 44 } }
            }) do
              stub_singleton(Telegram::Api, :edit_message_text, ->(*, **) { true }) do
                Telegram::Flows::AiAssistantFlow.process_text({ "chat" => { "id" => "656" }, "text" => "first" })
                Telegram::Flows::AiAssistantFlow.process_text({ "chat" => { "id" => "656" }, "text" => "second" })
              end
            end
          end
        end
      end

      assert_equal [], calls[0][:history]
      assert_equal [
        { role: "user", content: "first" },
        { role: "assistant", content: "ok" }
      ], calls[1][:history]
    end
  end

  test "back callback clears shared ai context" do
    with_memory_cache do
      Telegram::Helpers::Conversation.start("123", "flow" => "ai_assistant")
      Ai::ChatContextStore.append(channel: :telegram, key: "123", user_message: "hello", assistant_message: "hi")
      callback = { "id" => "cb1", "data" => "ai:back", "message" => { "message_id" => 77, "chat" => { "id" => "123" } } }

      stub_singleton(Telegram::Api, :answer_callback, ->(*) { true }) do
        stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(*, **) { true }) do
          assert Telegram::Flows::AiAssistantFlow.handle_callback(callback)
        end
      end

      assert_equal [], Ai::ChatContextStore.fetch(channel: :telegram, key: "123")
    end
  end

  test "record result callback sends prompt without calling ai" do
    with_memory_cache do
      user = User.new(email: "admin@example.test", telegram_chat_id: "987", admin: true)
      callback = { "id" => "cb2", "data" => "ai:snippet:record_result", "message" => { "message_id" => 78, "chat" => { "id" => "987" } } }
      sends = []

      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :ru) do
        stub_singleton(Telegram::Helpers::UserLookup, :find_user, user) do
          stub_singleton(Telegram::Api, :answer_callback, ->(*) { true }) do
            stub_singleton(Telegram::Api, :send_simple, ->(*args, **kwargs) {
              sends << [ args, kwargs ]
              true
            }) do
              stub_singleton(Ai::AssistantService, :new, ->(*) { flunk "AI should not be called for record result snippet" }) do
                assert Telegram::Flows::AiAssistantFlow.handle_callback(callback)
              end
            end
          end
        end
      end

      assert_equal "ai_assistant", Telegram::Helpers::Conversation.get("987")["flow"]
      assert_equal Telegram::I18n.t(:ai_snippet_record_result_prompt, locale: :ru), sends[0][0][1]
    end
  end

  test "structured record result message bypasses ai and records multiple matches" do
    with_memory_cache do
      admin = User.create!(email: "structured-admin@example.test", name: "Denis", telegram_username: "denis1011101", telegram_chat_id: "988", admin: true)
      User.create!(email: "structured-opponent-one@example.test", name: "Aleksandr", telegram_username: "AleksanderKorobkin")
      User.create!(email: "structured-opponent-two@example.test", name: "Keklil", telegram_username: "Keklil")
      Telegram::Helpers::Conversation.start("988", "flow" => "ai_assistant")
      sends = []
      text = <<~TEXT.strip
        Дата: 2026-04-08
        Часы: 1.5
        Команда A: @denis1011101
        Команда B: @AleksanderKorobkin
        Счет: 4:2

        Дата: 2026-04-08
        Часы: 1.5
        Команда A: @denis1011101
        Команда B: @Keklil
        Счет: 2:4
      TEXT

      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, :ru) do
        stub_singleton(Telegram::Helpers::UserLookup, :find_user, admin) do
          stub_singleton(Telegram::Api, :send_simple, ->(*args, **kwargs) {
            sends << [ args, kwargs ]
            true
          }) do
            stub_singleton(Ai::AssistantService, :new, ->(*) { flunk "AI should not be called for structured result messages" }) do
              assert Telegram::Flows::AiAssistantFlow.process_text({ "chat" => { "id" => "988" }, "text" => text })
            end
          end
        end
      end

      assert_equal 4, Match.where(mode: "singles", played_at: Date.new(2026, 4, 8).all_day).count
      assert_includes sends[0][0][1], "1. @denis1011101 won 4-2"
      assert_includes sends[0][0][1], "2. @Keklil won 2-4"
    end
  end

  private

  class FakeAssistantServiceFactory
    def initialize(answer_or_callable, calls = nil)
      @answer_or_callable = answer_or_callable
      @calls = calls
    end

    def call(*)
      FakeAssistantService.new(@answer_or_callable, @calls)
    end
    alias_method :new, :call
  end

  class FakeAssistantService
    def initialize(answer_or_callable, calls = nil)
      @answer_or_callable = answer_or_callable
      @calls = calls
    end

    def chat(message = nil, **kwargs)
      @calls << { message: message, history: kwargs[:history] } if @calls
      return @answer_or_callable.call if @answer_or_callable.respond_to?(:call)

      @answer_or_callable
    end
  end
end
