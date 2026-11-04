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

  test "notify_ugc_report returns true when telegram api succeeds" do
    stub_singleton(Telegram::AdminNotifier, :admin_recipient, -> { { chat_id: "123", locale: "en" } }) do
      stub_singleton(Telegram::Api, :send_simple, ->(*_args, **_kwargs) { { "ok" => true, "result" => {} } }) do
        delivered = Telegram::AdminNotifier.notify_ugc_report(
          target_type: "TrainingBlock",
          target_id: 1,
          author: "Author",
          reporter: "Reporter",
          reason: "Spam",
          url: "https://getcourt.test"
        )
        assert_equal true, delivered
      end
    end
  end

  test "notify_ugc_report returns false when telegram api rejects message" do
    stub_singleton(Telegram::AdminNotifier, :admin_recipient, -> { { chat_id: "123", locale: "en" } }) do
      stub_singleton(Telegram::Api, :send_simple, ->(*_args, **_kwargs) { { "ok" => false, "error_code" => 429, "description" => "Too Many Requests" } }) do
        delivered = Telegram::AdminNotifier.notify_ugc_report(
          target_type: "TrainingBlock",
          target_id: 1,
          author: "Author",
          reporter: "Reporter",
          reason: "Spam",
          url: "https://getcourt.test"
        )
        assert_equal false, delivered
      end
    end
  end

  test "notify_ugc_report returns false when admin recipient is missing" do
    stub_singleton(Telegram::AdminNotifier, :admin_recipient, -> { nil }) do
      delivered = Telegram::AdminNotifier.notify_ugc_report(
        target_type: "TrainingBlock",
        target_id: 1,
        author: "Author",
        reporter: "Reporter",
        reason: "Spam",
        url: "https://getcourt.test"
      )
      assert_equal false, delivered
    end
  end
end
