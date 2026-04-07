require "test_helper"
require "support/cache_helper"

class Ai::ChatContextStoreTest < ActiveSupport::TestCase
  include CacheHelper

  test "returns empty history when cache is blank" do
    with_memory_cache do
      assert_equal [], Ai::ChatContextStore.fetch(channel: :web, key: "session-1")
    end
  end

  test "stores rolling history with ttl" do
    with_memory_cache do
      4.times do |i|
        Ai::ChatContextStore.append(
          channel: :telegram,
          key: "chat-1",
          user_message: "user #{i}",
          assistant_message: "assistant #{i}"
        )
      end

      assert_equal [
        { role: "user", content: "user 1" },
        { role: "assistant", content: "assistant 1" },
        { role: "user", content: "user 2" },
        { role: "assistant", content: "assistant 2" },
        { role: "user", content: "user 3" },
        { role: "assistant", content: "assistant 3" }
      ], Ai::ChatContextStore.fetch(channel: :telegram, key: "chat-1")
    end
  end

  test "clears stored history" do
    with_memory_cache do
      Ai::ChatContextStore.append(
        channel: :web,
        key: "session-2",
        user_message: "hello",
        assistant_message: "hi"
      )

      Ai::ChatContextStore.clear(channel: :web, key: "session-2")

      assert_equal [], Ai::ChatContextStore.fetch(channel: :web, key: "session-2")
    end
  end
end
