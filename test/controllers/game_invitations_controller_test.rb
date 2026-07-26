require "test_helper"

class GameInvitationsControllerTest < ActionDispatch::IntegrationTest
  test "game owner can invite telegram users from web" do
    owner = users(:one)
    target = users(:two)
    game = games(:one)
    owner.update!(email: "invite-owner@example.com", telegram_chat_id: 90_001)
    target.update!(email: "invite-target@example.com", telegram_username: "@targetuser", telegram_chat_id: 90_002)
    game.update!(user: owner)

    post session_url, params: { email: owner.email }

    calls = []
    stub_singleton(Telegram::Api, :send_api, ->(*args) { calls << args; { "ok" => true } }) do
      post game_invitations_path(game), params: { usernames: "@targetuser" }
    end

    assert_redirected_to game_path(game)
    assert_equal 1, calls.size
    api, payload = calls.first
    assert_equal "sendMessage", api
    assert_equal target.telegram_chat_id.to_s, payload[:chat_id]
    assert_includes payload[:text], game_path(game)
    assert_equal "game:join_invited:#{game.id}", payload[:reply_markup][:inline_keyboard].first.first[:callback_data]
  end

  test "sent invite lists are remembered without order-only duplicates" do
    owner = users(:one)
    target = users(:two)
    game = games(:one)
    owner.update!(email: "invite-history@example.com", telegram_chat_id: 90_003)
    target.update!(email: "invite-history-target@example.com", telegram_username: "@targetuser", telegram_chat_id: 90_004)
    game.update!(user: owner)

    post session_url, params: { email: owner.email }

    stub_singleton(Telegram::Api, :send_api, ->(*) { { "ok" => true } }) do
      post game_invitations_path(game), params: { usernames: "@targetuser @friend" }
      post game_invitations_path(game), params: { usernames: "@friend @targetuser" }
    end

    assert_equal [ %w[friend targetuser] ], owner.reload.recent_invite_handles
  end

  test "non owner cannot invite users" do
    owner = users(:one)
    target = users(:two)
    game = games(:one)
    owner.update!(email: "invite-owner-forbidden@example.com")
    target.update!(email: "invite-target-forbidden@example.com")
    game.update!(user: owner)

    post session_url, params: { email: target.email }
    post game_invitations_path(game), params: { usernames: "@targetuser" }

    assert_response :forbidden
  end
end
