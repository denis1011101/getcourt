require "test_helper"

class ParticipantsManageFlowTest < ActiveSupport::TestCase
  test "new remove buttons use participation id callback prefix" do
    owner = User.create!(email: "tg_manage_owner@example.com", telegram_chat_id: "700001")
    participant = User.create!(email: "tg_manage_participant@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")
    participation = Participation.create!(game: game, user: participant, status: "approved")
    edited = nil

    stub_singleton(Telegram::Api, :answer_callback, ->(*) { true }) do
      stub_singleton(Telegram::Api, :edit_message_with_buttons, ->(*args) { edited = args }) do
        Telegram::Flows::Games::ParticipantsManageFlow.handle_callback(callback(owner.telegram_chat_id, "game:manage:#{game.id}:1"))
      end
    end

    buttons = edited[3]
    assert_includes edited[2], "Управление игроками"
    assert buttons.flatten.any? { |button| button[:callback_data] == "game:removep:#{game.id}:#{participation.id}:1" }
  end

  test "legacy remove callback treats id as user id" do
    owner = User.create!(id: 901_001, email: "tg_manage_legacy_owner@example.com", telegram_chat_id: "700002")
    target = User.create!(id: 901_002, email: "tg_manage_legacy_target@example.com")
    other = User.create!(id: 901_003, email: "tg_manage_legacy_other@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")
    wrong_participation = Participation.create!(id: target.id, game: game, user: other, status: "approved")
    target_participation = Participation.create!(id: 901_010, game: game, user: target, status: "approved")

    stub_telegram_api do
      Telegram::Flows::Games::ParticipantsManageFlow.handle_callback(callback(owner.telegram_chat_id, "game:remove:#{game.id}:#{target.id}:1"))
    end

    assert_not Participation.exists?(target_participation.id)
    assert Participation.exists?(wrong_participation.id)
  end

  private

  def callback(chat_id, data)
    {
      "id" => "callback-id",
      "from" => { "id" => chat_id },
      "message" => { "chat" => { "id" => chat_id }, "message_id" => 123 },
      "data" => data
    }
  end

  def stub_telegram_api(&block)
    stub_singleton(Telegram::Api, :answer_callback, ->(*) { true }) do
      stub_singleton(Telegram::Api, :send_simple, ->(*) { true }) do
        stub_singleton(Telegram::Api, :edit_message_with_buttons, ->(*) { true }, &block)
      end
    end
  end
end
