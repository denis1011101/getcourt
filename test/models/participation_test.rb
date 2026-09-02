require "test_helper"
require "support/cache_helper"

class ParticipationTest < ActiveSupport::TestCase
  include CacheHelper
  test "is invalid when same user joins same game twice" do
    duplicate = Participation.new(user: participations(:one).user, game: participations(:one).game)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already joined this game"
  end

  test "requires status" do
    participation = Participation.new(user: users(:one), game: games(:two), status: nil)

    assert_not participation.valid?
    assert_includes participation.errors[:status], "can't be blank"
  end

  test "guest is valid without user" do
    participation = Participation.new(game: games(:one), guest_name: "Alex Guest", status: "approved")

    assert participation.valid?
    assert participation.guest?
    assert_equal "Alex Guest", participation.display_name
  end

  test "registered participation cannot have guest name" do
    participation = Participation.new(user: users(:one), game: games(:two), guest_name: "Alex Guest")

    assert_not participation.valid?
    assert_includes participation.errors[:guest_name], "must be blank"
  end

  test "registered participation requires existing user" do
    participation = Participation.new(user_id: 987_654_321, game: games(:two), status: "approved")

    assert_not participation.valid?
    assert_includes participation.errors[:user], "can't be blank"
  end

  test "guest name is unique per game case-insensitively" do
    Participation.create!(game: games(:one), guest_name: "Alex Guest", status: "approved")
    duplicate = Participation.new(game: games(:one), guest_name: "alex guest", status: "approved")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:guest_name], "has already been taken"
  end

  test "guest name is limited to 50 characters" do
    participation = Participation.new(game: games(:one), guest_name: "a" * 51, status: "approved")

    assert_not participation.valid?
    assert_includes participation.errors[:guest_name], "is too long (maximum is 50 characters)"
  end

  test "joining a game turns on chat mode and shows the switch and leave buttons" do
    court = Court.create!(name: "Join Chat Court", city_name: "Yekaterinburg")
    owner = User.create!(email: "join-chat-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner", telegram_chat_id: 910_000_003)
    player = User.create!(email: "join-chat-player-#{SecureRandom.hex(4)}@example.com", name: "Player", telegram_chat_id: 910_000_001)
    game = Game.create!(court: court, user: owner, date: Date.current, kind: "game")
    sent = []

    with_memory_cache do
      stub_singleton(Telegram::Api, :send_with_buttons, ->(*args, **) { sent << args }) do
        Participation.create!(game: game, user: player, status: "approved", approved_at: Time.current)
      end

      assert_equal game.id, Telegram::Chat::Session.game_id(player.telegram_chat_id)
    end

    assert_equal 1, sent.size
    chat_id, text, buttons = sent.first
    assert_equal player.telegram_chat_id.to_s, chat_id
    assert_equal [ "chat:pick", "chat:exit" ], buttons.first.map { |button| button[:callback_data] }
    # В счётчике только владелец: себе сообщение не приходит.
    assert_includes text, "(1)"
  ensure
    game&.destroy
    [ owner, player ].compact.each(&:destroy)
    court&.destroy
  end

  test "a join request does not turn on chat mode until it is approved" do
    court = Court.create!(name: "Pending Chat Court", city_name: "Yekaterinburg")
    owner = User.create!(email: "pending-chat-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner")
    player = User.create!(email: "pending-chat-player-#{SecureRandom.hex(4)}@example.com", name: "Player", telegram_chat_id: 910_000_002)
    game = Game.create!(court: court, user: owner, date: Date.current, kind: "game")

    with_memory_cache do
      stub_singleton(Telegram::Api, :send_with_buttons, ->(*) { }) do
        participation = Participation.create!(game: game, user: player, status: "pending")
        assert_nil Telegram::Chat::Session.game_id(player.telegram_chat_id)

        participation.update!(status: "approved", approved_at: Time.current)
        assert_equal game.id, Telegram::Chat::Session.game_id(player.telegram_chat_id)
      end
    end
  ensure
    game&.destroy
    [ owner, player ].compact.each(&:destroy)
    court&.destroy
  end
end
