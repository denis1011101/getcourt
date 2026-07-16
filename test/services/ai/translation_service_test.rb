require "test_helper"

class Ai::TranslationServiceTest < ActiveSupport::TestCase
  test "returns nil for blank text" do
    assert_nil Ai::TranslationService.translate_to_english("")
    assert_nil Ai::TranslationService.translate_to_english(nil)
    assert_nil Ai::TranslationService.translate_to_english("   ")
  end

  test "returns translated content on success" do
    fake_message = Struct.new(:content).new("Draper on defeat by Opelka")
    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) { |_| fake_message }

    stub_singleton(Ai::GeminiKeys, :apply_current_key!, -> { }) do
      stub_singleton(RubyLLM, :chat, ->(_opts) { fake_chat }) do
        result = Ai::TranslationService.translate_to_english("Дрэйпер о поражении от Опелки")
        assert_equal "Draper on defeat by Opelka", result
      end
    end
  end

  test "returns nil and logs on unexpected error" do
    stub_singleton(Ai::GeminiKeys, :apply_current_key!, -> { }) do
      stub_singleton(RubyLLM, :chat, ->(_opts) { raise StandardError, "oops" }) do
        assert_nil Ai::TranslationService.translate_to_english("Привет")
      end
    end
  end
end
