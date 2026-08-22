require "test_helper"

class Telegram::PollerTest < ActiveSupport::TestCase
  test "inspect keeps the bot token out of logs and error messages" do
    poller = Telegram::Poller.new("123456:super-secret-token")

    assert_not_includes poller.inspect, "super-secret-token"
    assert_includes poller.inspect, "@offset"
  end

  test "refuses to start without a token" do
    assert_raises(RuntimeError) { Telegram::Poller.new("") }
  end
end
