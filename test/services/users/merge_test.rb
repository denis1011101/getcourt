require "test_helper"

class Users::MergeTest < ActiveSupport::TestCase
  test "moves history and archives the generated Telegram account" do
    target = users(:two)
    target.update_columns(email: "merge-target@example.com")
    donor = User.create!(
      email: "tg-#{SecureRandom.hex(8)}@telegram.getcourt",
      telegram_generated_email: true,
      telegram_chat_id: 777_001,
      telegram_username: "merge_donor",
      notification_channel: "telegram",
      coach: true
    )
    game = games(:one)
    game.update_columns(user_id: donor.id)
    opponent = users(:one)
    match = Match.create!(
      user: donor,
      opponent: opponent,
      game: game,
      mode: "singles",
      outcome: "win",
      played_at: Time.current
    )
    self_match = Match.create!(
      user: donor,
      opponent: target,
      game: game,
      mode: "singles",
      outcome: "win",
      played_at: Time.current
    )
    donor.player_statistic.update!(singles_games: 3, singles_wins: 2)
    target_games_before = target.player_statistic.singles_games.to_i
    enqueued_modes = []

    stub_singleton(RecalculateEloJob, :perform_later, ->(modes) { enqueued_modes << modes }) do
      Users::Merge.call(source: donor, target: target)
    end

    assert_equal target.id, game.reload.user_id
    assert_equal target.id, match.reload.user_id
    assert_not Match.exists?(self_match.id)
    assert_equal target_games_before + 3, target.player_statistic.reload.singles_games
    assert target.coach?
    assert_equal [ [ "singles" ] ], enqueued_modes
    assert_equal target.id, donor.reload.merged_into_id
    assert donor.merged_at.present?
    assert_nil donor.telegram_chat_id
    assert_nil donor.telegram_username
    assert_match(/\Amerged-#{donor.id}-/, donor.email)
  end
end
