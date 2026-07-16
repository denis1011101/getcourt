require "test_helper"

class Ai::GeminiKeysTest < ActiveSupport::TestCase
  test "rotates keys and retries a rate-limited operation" do
    attempts = 0
    applications = 0
    rotations = 0

    stub_singleton(Ai::GeminiKeys, :api_keys, [ "one", "two" ]) do
      stub_singleton(Ai::GeminiKeys, :apply_current_key!, -> { applications += 1 }) do
        stub_singleton(Ai::GeminiKeys, :rotate_key!, -> { rotations += 1 }) do
          result = Ai::GeminiKeys.with_rotation do
            attempts += 1
            raise RubyLLM::RateLimitError, "limited" if attempts == 1

            "ok"
          end

          assert_equal "ok", result
        end
      end
    end

    assert_equal 2, attempts
    assert_equal 2, applications
    assert_equal 1, rotations
  end

  test "limits retries even when more keys are configured" do
    attempts = 0
    rotations = 0

    stub_singleton(Ai::GeminiKeys, :api_keys, [ "one", "two", "three" ]) do
      stub_singleton(Ai::GeminiKeys, :apply_current_key!, nil) do
        stub_singleton(Ai::GeminiKeys, :rotate_key!, -> { rotations += 1 }) do
          assert_raises RubyLLM::RateLimitError do
            Ai::GeminiKeys.with_rotation(max_attempts: 2) do
              attempts += 1
              raise RubyLLM::RateLimitError, "limited"
            end
          end
        end
      end
    end

    assert_equal 2, attempts
    assert_equal 1, rotations
  end
end
