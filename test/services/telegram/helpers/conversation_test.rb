require "test_helper"
require "support/cache_helper"

class Telegram::Helpers::ConversationTest < ActiveSupport::TestCase
  include Telegram::Helpers
  include CacheHelper

  test "start writes state to cache" do
    with_memory_cache do
      chat_id = "conv_#{SecureRandom.hex(4)}"
      Conversation.start(chat_id, "step" => "ask_city")
      assert_equal "ask_city", Conversation.get(chat_id)["step"]
    end
  end

  test "get returns empty hash when no state exists" do
    with_memory_cache do
      assert_equal({}, Conversation.get("missing"))
    end
  end

  test "update merges into existing state without overwriting other keys" do
    with_memory_cache do
      chat_id = "conv_#{SecureRandom.hex(4)}"
      Conversation.start(chat_id, "a" => 1, "b" => 2)
      Conversation.update(chat_id, "b" => 99, "c" => 3)
      state = Conversation.get(chat_id)
      assert_equal 1,  state["a"]
      assert_equal 99, state["b"]
      assert_equal 3,  state["c"]
    end
  end

  test "finish returns state and removes it from cache" do
    with_memory_cache do
      chat_id = "conv_#{SecureRandom.hex(4)}"
      Conversation.start(chat_id, "step" => "ask_sports", "city" => "Moscow")
      state = Conversation.finish(chat_id)
      assert_equal "ask_sports", state["step"]
      assert_equal "Moscow",     state["city"]
      assert_equal({}, Conversation.get(chat_id))
    end
  end

  test "set_step updates step without losing other keys" do
    with_memory_cache do
      chat_id = "conv_#{SecureRandom.hex(4)}"
      Conversation.start(chat_id, "city" => "Kazan", "step" => "ask_city")
      Conversation.set_step(chat_id, "ask_sports")
      state = Conversation.get(chat_id)
      assert_equal "ask_sports", state["step"]
      assert_equal "Kazan",      state["city"]
    end
  end

  test "toggle_sport adds sport when not present" do
    with_memory_cache do
      chat_id = "conv_#{SecureRandom.hex(4)}"
      Conversation.start(chat_id, "selected_sports" => [])
      Conversation.toggle_sport(chat_id, "tennis")
      assert_includes Conversation.get(chat_id)["selected_sports"], "tennis"
    end
  end

  test "toggle_sport removes sport when already present" do
    with_memory_cache do
      chat_id = "conv_#{SecureRandom.hex(4)}"
      Conversation.start(chat_id, "selected_sports" => ["tennis", "padel"])
      Conversation.toggle_sport(chat_id, "tennis")
      assert_not_includes Conversation.get(chat_id)["selected_sports"], "tennis"
      assert_includes     Conversation.get(chat_id)["selected_sports"], "padel"
    end
  end

  test "set_skill stores skill level per sport" do
    with_memory_cache do
      chat_id = "conv_#{SecureRandom.hex(4)}"
      Conversation.start(chat_id)
      Conversation.set_skill(chat_id, "Tennis", "beginner")
      Conversation.set_skill(chat_id, "Padel", "intermediate")
      skills = Conversation.get(chat_id)["skills"]
      assert_equal "beginner",     skills["Tennis"]
      assert_equal "intermediate", skills["Padel"]
    end
  end

  test "set_notifications stores value" do
    with_memory_cache do
      chat_id = "conv_#{SecureRandom.hex(4)}"
      Conversation.start(chat_id)
      Conversation.set_notifications(chat_id, true)
      assert_equal true, Conversation.get(chat_id)["notifications"]
    end
  end
end
