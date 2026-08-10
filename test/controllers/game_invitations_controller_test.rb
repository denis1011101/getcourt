require "test_helper"

class GameInvitationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "game owner can invite telegram users from web" do
    owner = users(:one)
    target = users(:two)
    game = games(:one)
    owner.update!(email: "invite-owner@example.com", telegram_chat_id: 90_001)
    target.update!(email: "invite-target@example.com", telegram_username: "@targetuser", telegram_chat_id: 90_002, telegram_locale: "en", notification_channel: "telegram")
    game.update!(user: owner, with_coach: true)

    post session_url, params: { email: owner.email }

    calls = []
    stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { calls << args; { "ok" => true } }) do
      post game_invitations_path(game), params: { usernames: "@targetuser" }
    end

    assert_redirected_to game_path(game)
    assert_equal 1, calls.size
    chat_id, text, buttons = calls.first
    assert_equal target.telegram_chat_id, chat_id
    assert_includes text, game_path(game)
    assert_includes text, "You are invited to join:"
    assert_includes text, " — With coach\n"
    assert_equal "Join ##{game.id}", buttons.first.first[:text]
    assert_equal "game:join_invited:#{game.id}", buttons.first.first[:callback_data]
  end

  test "invitation is localized in Russian" do
    payload = invitation_payload_for("ru", chat_id: 90_007)

    assert_includes payload[:text], "Вас приглашают присоединиться:"
    assert_includes payload[:text], "Теннис ##{games(:one).id}"
    assert_equal "Присоединиться ##{games(:one).id}", payload[:reply_markup][:inline_keyboard].first.first[:text]
  end

  test "invitation is localized in Spanish" do
    payload = invitation_payload_for("es", chat_id: 90_008)

    assert_includes payload[:text], "Te han invitado a unirte:"
    assert_includes payload[:text], "Tenis ##{games(:one).id}"
    assert_equal "Unirse ##{games(:one).id}", payload[:reply_markup][:inline_keyboard].first.first[:text]
  end

  test "invite omits coach mark when game has no coach" do
    owner = users(:one)
    target = users(:two)
    game = games(:one)
    owner.update!(email: "invite-no-coach-owner@example.com")
    target.update!(email: "invite-no-coach-target@example.com", telegram_username: "@targetuser", telegram_chat_id: 90_005, telegram_locale: "en", notification_channel: "telegram")
    game.update!(user: owner, with_coach: false)

    post session_url, params: { email: owner.email }

    calls = []
    stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { calls << args; { "ok" => true } }) do
      post game_invitations_path(game), params: { usernames: "@targetuser" }
    end

    assert_not_includes calls.first.second, " — With coach"
  end

  test "sent invite lists are remembered without order-only duplicates" do
    owner = users(:one)
    target = users(:two)
    game = games(:one)
    owner.update!(email: "invite-history@example.com", telegram_chat_id: 90_003)
    target.update!(email: "invite-history-target@example.com", telegram_username: "@targetuser", telegram_chat_id: 90_004, notification_channel: "telegram")
    game.update!(user: owner)

    post session_url, params: { email: owner.email }

    stub_singleton(Telegram::Api, :send_with_buttons, ->(*) { { "ok" => true } }) do
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

  test "invitation uses email when selected" do
    owner = users(:one)
    target = users(:two)
    game = games(:one)
    owner.update!(email: "invite-email-owner@example.com", name: "Owner")
    target.update!(email: "invite-email-target@example.com", telegram_username: "@targetuser", notification_channel: "email", locale: "en")
    game.update!(user: owner)
    post session_url, params: { email: owner.email }

    assert_enqueued_emails 1 do
      post game_invitations_path(game), params: { usernames: "@targetuser" }
    end

    assert_redirected_to game_path(game)
  end

  private
    def invitation_payload_for(locale, chat_id:)
      owner = users(:one)
      target = users(:two)
      game = games(:one)
      owner.update!(email: "invite-#{locale}-owner@example.com")
      target.update!(email: "invite-#{locale}-target@example.com", telegram_username: "@targetuser", telegram_chat_id: chat_id, telegram_locale: locale, notification_channel: "telegram")
      game.update!(user: owner, sport: "Tennis", with_coach: true)
      post session_url, params: { email: owner.email }
      calls = []

      stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { calls << args; { "ok" => true } }) do
        post game_invitations_path(game), params: { usernames: "@targetuser" }
      end

      { text: calls.first.second, reply_markup: { inline_keyboard: calls.first.third } }
    end
end
