require "test_helper"

class Ai::ScoreFromPhotoServiceTest < ActiveSupport::TestCase
  test "extracts and normalizes a structured score from a photo" do
    response = Struct.new(:content).new({
      "sets" => [
        { "top" => 6, "bottom" => 4 },
        { "top" => 6, "bottom" => 7, "tiebreak_top" => 5 },
        { "top" => "10", "bottom" => "8" }
      ],
      "top_names" => [ " Ivan " ],
      "bottom_names" => [ "Petr" ]
    })
    fake_chat = FakeRubyLLMChat.new { response }

    stub_singleton(RubyLLM, :chat, ->(**kwargs) {
      assert_equal "gemini-2.5-flash", kwargs[:model]
      fake_chat
    }) do
      result = Ai::ScoreFromPhotoService.new.call("/tmp/score.jpg", timeout_seconds: 1)

      assert_equal Ai::ScoreFromPhotoService::ScoreSchema, fake_chat.schema
      assert_equal "/tmp/score.jpg", fake_chat.photo_path
      assert_includes fake_chat.prompt, "top and bottom"
      assert_equal [
        { top: 6, bottom: 4 },
        { top: 6, bottom: 7, tiebreak_top: 5 },
        { top: 10, bottom: 8 }
      ], result[:sets]
      assert_equal [ "Ivan" ], result[:top_names]
      assert_equal [ "Petr" ], result[:bottom_names]
    end
  end

  test "rotates the Gemini key after a rate limit" do
    attempts = 0
    rotations = 0
    fake_chat = FakeRubyLLMChat.new do
      attempts += 1
      raise RubyLLM::RateLimitError, "limited" if attempts == 1

      Struct.new(:content).new({ sets: [], top_names: [], bottom_names: [] })
    end

    stub_singleton(Ai::GeminiKeys, :api_keys, [ "one", "two" ]) do
      stub_singleton(Ai::GeminiKeys, :apply_current_key!, nil) do
        stub_singleton(Ai::GeminiKeys, :rotate_key!, -> { rotations += 1 }) do
          stub_singleton(RubyLLM, :chat, ->(**) { fake_chat }) do
            result = Ai::ScoreFromPhotoService.new.call("/tmp/score.jpg", timeout_seconds: 1)

            assert_empty result[:sets]
          end
        end
      end
    end

    assert_equal 2, attempts
    assert_equal 1, rotations
  end

  test "returns an empty result when the model response is not an object" do
    [ [], 42 ].each do |content|
      response = Struct.new(:content).new(content)
      fake_chat = FakeRubyLLMChat.new { response }

      stub_singleton(RubyLLM, :chat, ->(**) { fake_chat }) do
        result = Ai::ScoreFromPhotoService.new.call("/tmp/score.jpg", timeout_seconds: 1)

        assert_empty result[:sets]
        assert_empty result[:top_names]
        assert_empty result[:bottom_names]
      end
    end
  end

  private

  class FakeRubyLLMChat
    attr_reader :schema, :prompt, :photo_path

    def initialize(&response)
      @response = response
    end

    def with_schema(schema)
      @schema = schema
      self
    end

    def ask(prompt, with:)
      @prompt = prompt
      @photo_path = with
      @response.call
    end
  end
end
