require "test_helper"

class Telegram::AdminNotifierTest < ActiveSupport::TestCase
  test "court suggestion notification is text with review url" do
    suggestion = court_suggestions(:pending)
    sent = nil

    stub_singleton(Telegram::AdminNotifier, :send_message, ->(text) { sent = text }) do
      Telegram::AdminNotifier.notify_court_suggestion(suggestion, base_url: "https://getcourt.test")
    end

    assert_includes sent, suggestion.court.name
    assert_includes sent, "https://getcourt.test/court_suggestions/#{suggestion.id}"
  end
end
