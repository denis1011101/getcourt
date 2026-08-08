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
    assert_not donor.coach?
  end

  test "rewrites the player ids kept inside match stats" do
    target = users(:two)
    target.update_columns(email: "merge-stats-target@example.com")
    donor = User.create!(
      email: "tg-#{SecureRandom.hex(8)}@telegram.getcourt",
      telegram_generated_email: true
    )
    ally = users(:one)
    foe = User.create!(email: "merge-foe@example.com")
    foe2 = User.create!(email: "merge-foe2@example.com")
    game = games(:one)
    played_at = 1.day.ago

    team_a = [ donor.id, ally.id ]
    team_b = [ foe.id, foe2.id ]
    rows = [ [ donor, team_a ], [ ally, team_a ], [ foe, team_b ], [ foe2, team_b ] ].map do |user, own_team|
      opponents = own_team == team_a ? team_b : team_a
      Match.create!(
        user: user,
        opponent_id: opponents.first,
        game: game,
        mode: "doubles",
        outcome: own_team == team_a ? "win" : "loss",
        played_at: played_at,
        stats: {
          "entered_by" => donor.id,
          "team_a_ids" => team_a,
          "team_b_ids" => team_b,
          "partner_id" => (own_team - [ user.id ]).first,
          "opponent_ids" => opponents
        }
      )
    end

    stub_singleton(RecalculateEloJob, :perform_later, ->(_modes) { true }) do
      Users::Merge.call(source: donor, target: target)
    end

    donor_row, ally_row = rows.first(2).map(&:reload)
    assert_equal [ target.id, ally.id ], donor_row.stats["team_a_ids"]
    assert_equal [ target.id, ally.id ], ally_row.stats["team_a_ids"]
    assert_equal target.id, donor_row.stats["entered_by"]
    assert_equal ally.id, donor_row.stats["partner_id"]
    assert_equal target.id, ally_row.stats["partner_id"]

    PlayerStatistic.recalculate_elo_for_mode!("doubles")
    assert PlayerStatistic.find_by(user_id: target.id)&.doubles_rating.present?,
           "merged account must be rated for the games it inherited"
  end

  test "drops a doubles event where both accounts played against each other" do
    target = users(:two)
    target.update_columns(email: "merge-doubles-target@example.com")
    donor = User.create!(
      email: "tg-#{SecureRandom.hex(8)}@telegram.getcourt",
      telegram_generated_email: true
    )
    ally = users(:one)
    foe = User.create!(email: "merge-doubles-foe@example.com")
    game = games(:one)
    played_at = 2.days.ago

    team_a = [ donor.id, ally.id ]
    team_b = [ target.id, foe.id ]
    match_ids = [ [ donor, team_a ], [ ally, team_a ], [ target, team_b ], [ foe, team_b ] ].map do |user, own_team|
      opponents = own_team == team_a ? team_b : team_a
      Match.create!(
        user: user,
        opponent_id: opponents.first,
        game: game,
        mode: "doubles",
        outcome: own_team == team_a ? "win" : "loss",
        played_at: played_at,
        stats: { "team_a_ids" => team_a, "team_b_ids" => team_b, "opponent_ids" => opponents }
      ).id
    end

    stub_singleton(RecalculateEloJob, :perform_later, ->(_modes) { true }) do
      Users::Merge.call(source: donor, target: target)
    end

    assert_empty Match.where(id: match_ids), "an event a player shares with themselves must be dropped"
  end
end
