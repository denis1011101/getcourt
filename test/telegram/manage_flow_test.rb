require "test_helper"

class ManageFlowTest < ActiveSupport::TestCase
  test "delegates prebooking notification callbacks" do
    callbacks = [
      { "data" => "game:approve_all_prebookings:1:2" },
      { "data" => "game:reject_all_prebookings:1:2" }
    ]
    handled = []

    stub_singleton(Telegram::Flows::Games::Manage::PrebookApproveFlow, :handle_callback, ->(callback) { handled << callback; true }) do
      callbacks.each do |callback|
        assert Telegram::Flows::Games::ManageFlow.handle_callback(callback)
      end
    end

    assert_equal callbacks, handled
  end
end
