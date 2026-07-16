require "test_helper"

class PlayerStatistics::SyncMatchGroupServiceTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "sync_group_owner@example.com", name: "Owner")
    @opponent = User.create!(email: "sync_group_opponent@example.com", name: "Opponent")
    @game = Game.create!(
      court: courts(:one),
      user: @owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )

    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: @game,
      actor: @owner,
      mode: "singles",
      team_a_ids: [ @owner.id ],
      team_b_ids: [ @opponent.id ],
      result: :a,
      played_at: @game.date.to_time,
      score: "6-4 6-4",
      force_new: true
    )
    @group_id = Match.where(game_id: @game.id).first.stats.to_h.fetch("match_group_id")
  end

  test "updates score and winner without duplicating matches" do
    synced = sync(result: :b, score: "4-6 4-6")

    assert synced
    assert_equal 2, Match.where(game_id: @game.id).count
    assert_equal [ "4-6 4-6" ], Match.where(game_id: @game.id).pluck(:score).uniq
    assert_equal "loss", Match.find_by!(game_id: @game.id, user: @owner).outcome
    assert_equal "win", Match.find_by!(game_id: @game.id, user: @opponent).outcome

    assert_equal 0, @owner.player_statistic.reload.singles_wins
    assert_equal 1, @owner.player_statistic.singles_losses
    assert_equal 1, @opponent.player_statistic.reload.singles_wins
    assert_equal 1, @owner.player_statistic.singles_games
  end

  test "removes matches for players taken off the teams" do
    replacement = User.create!(email: "sync_group_replacement@example.com", name: "Replacement")

    synced = sync(team_b_ids: [ replacement.id ], result: :a, score: "6-4 6-4")

    assert synced
    assert_nil Match.find_by(game_id: @game.id, user: @opponent)
    replacement_match = Match.find_by!(game_id: @game.id, user: replacement)
    assert_equal "loss", replacement_match.outcome
    assert_equal @group_id, replacement_match.stats.to_h["match_group_id"]

    opponent_stats = @opponent.player_statistic.reload
    assert_equal 0, opponent_stats.singles_games
    assert_equal 0, opponent_stats.singles_losses
    assert_equal 1, replacement.player_statistic.reload.singles_games
  end

  test "returns false for an unknown group" do
    assert_not sync(group_id: "missing", result: :a, score: "6-0 6-0")
    assert_equal [ "6-4 6-4" ], Match.where(game_id: @game.id).pluck(:score).uniq
  end

  test "replacing a guest clears stale guest names and partner from stats" do
    guest_game = Game.create!(court: courts(:one), user: @owner, date: Date.yesterday, time: "11:00", with_coach: false)
    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: guest_game,
      actor: @owner,
      mode: "singles",
      team_a_ids: [ @owner.id ],
      team_b_ids: [],
      team_b_guest_names: [ "Old Guest" ],
      result: :a,
      played_at: guest_game.date.to_time,
      score: "6-1 6-1",
      force_new: true
    )
    group_id = Match.find_by!(game_id: guest_game.id, user: @owner).stats.to_h.fetch("match_group_id")

    synced = PlayerStatistics::SyncMatchGroupService.new(
      game: guest_game,
      actor: @owner,
      group_id: group_id,
      mode: "singles",
      team_a_ids: [ @owner.id ],
      team_b_ids: [ @opponent.id ],
      result: :a,
      played_at: guest_game.date.to_time,
      score: "6-1 6-1"
    ).call

    assert synced
    stats = Match.find_by!(game_id: guest_game.id, user: @owner).stats.to_h
    assert_empty Array(stats["team_b_guest_names"])
    assert_nil stats["partner_id"]
    assert_equal [ @opponent.id ], stats["opponent_ids"]

    group = PlayerStatistics::MatchGroups.for_game(guest_game).find { |g| g[:group_id] == group_id }
    assert_empty group[:team_b_guest_names]
    assert_equal [ @opponent.id ], group[:team_b_ids]
  end

  test "does not double-decrement counters for duplicated rows in a group" do
    PlayerStatistics::UpsertMatchForGameService.new(
      user: @opponent, game: @game, actor: @owner, mode: "singles",
      outcome: "loss", played_at: @game.date.to_time, score: "6-4 6-4",
      stats: { "team_a_ids" => [ @owner.id ], "team_b_ids" => [ @opponent.id ], "match_group_id" => @group_id },
      force_new: true
    ).call
    other_game = Game.create!(court: courts(:one), user: @owner, date: Date.yesterday, time: "12:00", with_coach: false)
    PlayerStatistics::UpsertMatchForGameService.new(
      user: @opponent, game: other_game, actor: @owner, mode: "singles",
      outcome: "win", played_at: other_game.date.to_time, score: "6-2 6-2",
      stats: { "team_a_ids" => [ @opponent.id ] },
      force_new: true
    ).call
    assert_equal 3, @opponent.player_statistic.reload.singles_games

    replacement = User.create!(email: "sync_group_dedup@example.com", name: "Dedup")
    synced = sync(team_b_ids: [ replacement.id ], result: :a, score: "6-4 6-4")

    assert synced
    assert_nil Match.find_by(game_id: @game.id, user: @opponent)
    assert_equal 1, @opponent.player_statistic.reload.singles_games
  end

  test "keeps training counter when a stats entry already covers the visit" do
    coach_game = Game.create!(court: courts(:one), user: @owner, date: Date.yesterday, time: "13:00", with_coach: true)
    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: coach_game,
      actor: @owner,
      mode: "singles",
      team_a_ids: [ @owner.id ],
      team_b_ids: [ @opponent.id ],
      result: :a,
      played_at: coach_game.date.to_time,
      score: "6-3 6-3",
      force_new: true
    )
    assert_equal 1, @opponent.player_statistic.reload.individual_training

    PlayerStatisticEntry.create!(
      user: @opponent, game: coach_game, actor: @owner,
      recorded_at: Time.current, source: "web", data: { "hours" => 1.0 }
    )
    group_id = Match.find_by!(game_id: coach_game.id, user: @owner).stats.to_h.fetch("match_group_id")

    replacement = User.create!(email: "sync_group_coach@example.com", name: "Coach Sub")
    synced = PlayerStatistics::SyncMatchGroupService.new(
      game: coach_game,
      actor: @owner,
      group_id: group_id,
      mode: "singles",
      team_a_ids: [ @owner.id ],
      team_b_ids: [ replacement.id ],
      result: :a,
      played_at: coach_game.date.to_time,
      score: "6-3 6-3"
    ).call

    assert synced
    assert_equal 1, @opponent.player_statistic.reload.individual_training
  end

  private

  def sync(result:, score:, team_a_ids: [ @owner.id ], team_b_ids: [ @opponent.id ], group_id: @group_id)
    PlayerStatistics::SyncMatchGroupService.new(
      game: @game,
      actor: @owner,
      group_id: group_id,
      mode: "singles",
      team_a_ids: team_a_ids,
      team_b_ids: team_b_ids,
      result: result,
      played_at: @game.date.to_time,
      score: score
    ).call
  end
end
