require "test_helper"

class Telegram::Flows::Games::Manage::JoinFlowTest < ActiveSupport::TestCase
  test "uses the actor locale for the callback and owner locale for the request" do
    owner = users(:one)
    requester = users(:two)
    game = games(:one)
    owner.update!(email: "join-owner@example.com", telegram_chat_id: 81_001, telegram_locale: "en")
    requester.update!(email: "join-requester@example.com", telegram_chat_id: 81_002, telegram_locale: "es")
    game.update!(user: owner)
    game.participations.where(user: requester).delete_all
    calls = []
    poller = Object.new
    poller.define_singleton_method(:send_api) { |method, payload| calls << [ method, payload ] }
    callback = {
      "id" => "callback-id",
      "data" => "game:join:#{game.id}",
      "from" => { "id" => requester.telegram_chat_id },
      "message" => { "chat" => { "id" => requester.telegram_chat_id }, "message_id" => 10 }
    }

    stub_singleton(Telegram::Poller, :new, -> { poller }) do
      stub_singleton(Telegram::Handlers::GamesHandler, :show_game, ->(*) { }) do
        Telegram::Flows::Games::Manage::JoinFlow.handle_callback(callback)
      end
    end

    callback_call = calls.find { |method, _| method == "answerCallbackQuery" }
    owner_call = calls.find { |method, payload| method == "sendMessage" && payload[:chat_id] == owner.telegram_chat_id }
    assert_equal "Solicitud para unirse enviada", callback_call.second[:text]
    assert_includes owner_call.second[:text], "Join request for Game"
    assert_equal "Approve", owner_call.second.dig(:reply_markup, :inline_keyboard, 0, 0, :text)
  end
end
