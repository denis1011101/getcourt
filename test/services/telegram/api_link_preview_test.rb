require "test_helper"

class TelegramApiLinkPreviewTest < ActiveSupport::TestCase
  test "sendMessage asks telegram not to draw a link preview" do
    assert_equal Telegram::Api::LINK_PREVIEW_DISABLED, captured_params { |chat| Telegram::Api.send_simple(chat, "text") }["link_preview_options"]
    assert_equal Telegram::Api::LINK_PREVIEW_DISABLED, captured_params { |chat| Telegram::Api.send_with_buttons(chat, "text", []) }["link_preview_options"]
  end

  # Флоу шлют сообщения через send_api, мимо именованных отправителей: превью
  # выключает сам транспорт, поэтому помнить о нём в каждом флоу не нужно.
  test "a message sent by a flow gets no link preview either" do
    params = captured_params { |chat| Telegram::Api.send_api("sendMessage", { chat_id: chat, text: "text" }) }

    assert_equal Telegram::Api::LINK_PREVIEW_DISABLED, params["link_preview_options"]
  end

  test "editing a message does not bring the preview back" do
    assert_equal Telegram::Api::LINK_PREVIEW_DISABLED, captured_params { |chat| Telegram::Api.edit_message_text(chat, 7, "text") }["link_preview_options"]
    assert_equal Telegram::Api::LINK_PREVIEW_DISABLED, captured_params { |chat| Telegram::Api.edit_message_with_buttons(chat, "7", "text", []) }["link_preview_options"]
  end

  test "a caller that wants the preview can still ask for it" do
    params = captured_params { |chat| Telegram::Api.send_simple(chat, "text", link_preview: true) }

    assert_equal Telegram::Api::LINK_PREVIEW_ENABLED, params["link_preview_options"]
  end

  test "methods without a message text are left alone" do
    params = captured_params { |_chat| Telegram::Api.answer_callback("cb-1") }

    assert_not params.key?("link_preview_options")
  end

  private
    def captured_params
      params = nil
      with_token("test-token") do
        stub_singleton(Net::HTTP, :post_form, ->(_uri, sent) { params = sent; response }) do
          yield 42
        end
      end
      params
    end

    def response
      Struct.new(:body).new({ "ok" => true }.to_json)
    end

    # Без токена post не доходит до запроса, а проверяем мы именно параметры запроса.
    def with_token(token)
      original = Telegram::Api::TOKEN
      Telegram::Api.send(:remove_const, :TOKEN)
      Telegram::Api.const_set(:TOKEN, token)
      yield
    ensure
      Telegram::Api.send(:remove_const, :TOKEN)
      Telegram::Api.const_set(:TOKEN, original)
    end
end
