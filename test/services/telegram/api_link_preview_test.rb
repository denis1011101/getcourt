require "test_helper"

class TelegramApiLinkPreviewTest < ActiveSupport::TestCase
  test "sendMessage asks telegram not to draw a link preview" do
    assert_equal Telegram::Api::LINK_PREVIEW_DISABLED, captured_params { |chat| Telegram::Api.send_simple(chat, "text") }["link_preview_options"]
    assert_equal Telegram::Api::LINK_PREVIEW_DISABLED, captured_params { |chat| Telegram::Api.send_with_buttons(chat, "text", []) }["link_preview_options"]
  end

  test "a caller that wants the preview can still ask for it" do
    params = captured_params { |chat| Telegram::Api.send_simple(chat, "text", link_preview: true) }

    assert_nil params["link_preview_options"]
  end

  private
    def captured_params
      params = nil
      stub_singleton(Telegram::Api, :post, ->(_path, sent) { params = sent }) do
        yield 42
      end
      params
    end
end
