require "test_helper"

class TelegramGamesInviteFlowTest < ActiveSupport::TestCase
  test "coach accepts invitation from telegram callback" do
    coach = User.create!(email: "coach-callback@example.com", coach: true, telegram_chat_id: 94_001)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      coach: coach,
      with_coach: true,
      date: Date.tomorrow
    )
    poller = Object.new
    poller.define_singleton_method(:send_api) { |*, **| { "ok" => true } }
    callback = {
      "id" => "callback-1",
      "data" => "game:coach_accept:#{game.id}",
      "from" => { "id" => coach.telegram_chat_id },
      "message" => { "chat" => { "id" => coach.telegram_chat_id } }
    }

    result = stub_singleton(Telegram::Poller, :new, poller) do
      Telegram::Flows::Games::InviteFlow.handle_callback(callback)
    end

    assert result
    assert game.reload.coach_accepted?
  ensure
    coach&.destroy
  end
end
