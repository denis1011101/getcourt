require "test_helper"

class Telegram::AdminNotifierTest < ActiveSupport::TestCase
  test "court suggestion notification is localized and sent through Telegram API" do
    suggestion = court_suggestions(:pending)
    sent = nil

    stub_singleton(Telegram::AdminNotifier, :admin_recipient, -> { { chat_id: "123", locale: "en" } }) do
      stub_singleton(Telegram::Api, :send_simple, ->(*args, **kwargs) { sent = [ args, kwargs ] }) do
        Telegram::AdminNotifier.notify_court_suggestion(suggestion, base_url: "https://getcourt.test")
      end
    end

    args, kwargs = sent
    assert_equal "123", args.first
    assert_includes args.second, suggestion.court.name
    assert_includes args.second, "https://getcourt.test/court_suggestions/#{suggestion.id}"
    assert_nil kwargs[:parse_mode]
  end
end
