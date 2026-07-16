require "test_helper"

class PlayerStatisticsControllerTest < ActionDispatch::IntegrationTest
  test "game show renders localized guest label in stats form" do
    post session_url, params: { email: "stats_guest_form_owner@example.com" }
    owner = User.find_by!(email: "stats_guest_form_owner@example.com")

    User.create!(name: "Addable Player", email: "stats_guest_form_addable@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )

    get game_url(game)

    assert_response :success
    assert_includes response.body, "Guest (not registered)"
    assert_includes response.body, "Add registered player"
  end

  test "game show renders saved guest as stats checkbox" do
    post session_url, params: { email: "stats_saved_guest_owner@example.com" }
    owner = User.find_by!(email: "stats_saved_guest_owner@example.com")
    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )
    Participation.create!(game: game, guest_name: "Saved Guest", status: "approved")

    get game_url(game)

    assert_response :success
    assert_includes response.body, "Saved Guest"
    assert_includes response.body, "team_a_guest_names"
    assert_includes response.body, "(guest)"
  end

  test "score upsert increments games even when stats entry already exists for normal game" do
    post session_url, params: { email: "stats_owner@example.com" }
    owner = User.find_by!(email: "stats_owner@example.com")
    participant = User.create!(email: "stats_participant@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )
    Participation.create!(game: game, user: participant, status: "approved")

    post game_player_statistics_url(game), params: {
      statistics: { hours: "1.5" }
    }

    assert_redirected_to game_path(game)
    assert_equal 1, PlayerStatisticEntry.where(game: game, user: participant).count

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-4 6-4",
          team_a_user_ids: [ owner.id ],
          team_b_user_ids: [ participant.id ],
          winner_team: "b"
        }
      }
    }

    assert_redirected_to game_path(game)

    participant_stats = participant.player_statistic.reload
    owner_stats = owner.player_statistic.reload
    assert_equal 1, participant_stats.singles_games
    assert_equal 1, participant_stats.singles_wins
    assert_equal 0, participant_stats.singles_losses
    assert_equal 1516.0, participant_stats.singles_rating
    assert_equal 1484.0, owner_stats.singles_rating
  end

  test "score upsert recalculates doubles elo for all participants" do
    post session_url, params: { email: "stats_owner_doubles@example.com" }
    owner = User.find_by!(email: "stats_owner_doubles@example.com")
    partner = User.create!(email: "stats_partner_doubles@example.com")
    opponent_one = User.create!(email: "stats_opponent_one_doubles@example.com")
    opponent_two = User.create!(email: "stats_opponent_two_doubles@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "11:00",
      with_coach: false
    )
    Participation.create!(game: game, user: partner, status: "approved")
    Participation.create!(game: game, user: opponent_one, status: "approved")
    Participation.create!(game: game, user: opponent_two, status: "approved")

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-4 3-6 10-8",
          team_a_user_ids: [ owner.id, partner.id ],
          team_b_user_ids: [ opponent_one.id, opponent_two.id ],
          winner_team: "a"
        }
      }
    }

    assert_redirected_to game_path(game)

    assert_equal 1516.0, owner.player_statistic.reload.doubles_rating
    assert_equal 1516.0, partner.player_statistic.reload.doubles_rating
    assert_equal 1484.0, opponent_one.player_statistic.reload.doubles_rating
    assert_equal 1484.0, opponent_two.player_statistic.reload.doubles_rating
  end

  test "score upsert records singles match against guest without elo" do
    post session_url, params: { email: "stats_guest_owner@example.com" }
    owner = User.find_by!(email: "stats_guest_owner@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-4 6-4",
          team_a_user_ids: [ owner.id ],
          team_b_guests: "Vasya",
          winner_team: "a"
        }
      }
    }

    assert_redirected_to game_path(game)
    match = Match.find_by!(game: game, user: owner)
    assert_equal [ "Vasya" ], match.stats["team_b_guest_names"]

    owner_stats = owner.player_statistic.reload
    assert_equal 1, owner_stats.singles_games
    assert_equal 1, owner_stats.singles_wins
    assert_nil owner_stats.singles_rating
  end

  test "score upsert merges guest name checkboxes with text field" do
    post session_url, params: { email: "stats_guest_checkbox_owner@example.com" }
    owner = User.find_by!(email: "stats_guest_checkbox_owner@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-4 6-4",
          team_a_user_ids: [ owner.id ],
          team_b_guest_names: [ "Saved Guest" ],
          team_b_guests: "Typed Guest",
          winner_team: "a"
        }
      }
    }

    assert_redirected_to game_path(game)
    match = Match.find_by!(game: game, user: owner)
    assert_equal [ "Typed Guest", "Saved Guest" ], match.stats["team_b_guest_names"]
    assert_nil owner.player_statistic.reload.singles_rating
  end

  test "score upsert records match for registered non-participant" do
    post session_url, params: { email: "stats_non_participant_owner@example.com" }
    owner = User.find_by!(email: "stats_non_participant_owner@example.com")
    outsider = User.create!(name: "Outsider", email: "stats_non_participant_outsider@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-4 6-4",
          team_a_user_ids: [ owner.id ],
          team_b_user_ids: [ outsider.id ],
          winner_team: "a"
        }
      }
    }

    assert_redirected_to game_path(game)
    assert Match.find_by!(game: game, user: outsider)

    outsider_stats = outsider.player_statistic.reload
    owner_stats = owner.player_statistic.reload
    assert_equal 1, outsider_stats.singles_games
    assert_equal 1, owner_stats.singles_wins
  end

  test "score upsert drops non-existent user ids" do
    post session_url, params: { email: "stats_nonexistent_owner@example.com" }
    owner = User.find_by!(email: "stats_nonexistent_owner@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )

    assert_no_difference("Match.count") do
      post game_player_statistics_url(game), params: {
        matches: {
          "0" => {
            score: "6-4 6-4",
            team_a_user_ids: [ owner.id ],
            team_b_user_ids: [ 999_999 ],
            winner_team: "a"
          }
        }
      }
    end

    assert_redirected_to game_path(game)
  end

  test "score upsert skips match when both teams are guests" do
    post session_url, params: { email: "stats_all_guest_owner@example.com" }
    owner = User.find_by!(email: "stats_all_guest_owner@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )

    assert_no_difference("Match.count") do
      post game_player_statistics_url(game), params: {
        matches: {
          "0" => {
            score: "6-4",
            team_a_guests: "Guest A",
            team_b_guests: "Guest B",
            winner_team: "a"
          }
        }
      }
    end

    assert_redirected_to game_path(game)
  end

  test "score upsert records doubles match with guest without elo" do
    post session_url, params: { email: "stats_guest_doubles_owner@example.com" }
    owner = User.find_by!(email: "stats_guest_doubles_owner@example.com")
    partner = User.create!(email: "stats_guest_doubles_partner@example.com")
    opponent = User.create!(email: "stats_guest_doubles_opponent@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "11:00",
      with_coach: false
    )
    Participation.create!(game: game, user: partner, status: "approved")
    Participation.create!(game: game, user: opponent, status: "approved")

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-4 3-6 10-8",
          team_a_user_ids: [ owner.id, partner.id ],
          team_b_user_ids: [ opponent.id ],
          team_b_guests: "Guest Partner",
          winner_team: "a"
        }
      }
    }

    assert_redirected_to game_path(game)

    assert_equal 1, owner.player_statistic.reload.doubles_games
    assert_equal 1, partner.player_statistic.reload.doubles_games
    assert_equal 1, opponent.player_statistic.reload.doubles_games
    assert_nil owner.player_statistic.reload.doubles_rating
    assert_nil partner.player_statistic.reload.doubles_rating
    assert_nil opponent.player_statistic.reload.doubles_rating
  end

  test "manual singles upsert without a game keeps separate matches on the same day" do
    denis = User.create!(email: "manual_stats_denis@example.com", name: "Denis")
    opponent_one = User.create!(email: "manual_stats_opponent_one@example.com", name: "Aleksandr")
    opponent_two = User.create!(email: "manual_stats_opponent_two@example.com", name: "Keklil")
    played_at = Time.zone.parse("2026-04-08 23:59:59")

    PlayerStatistics::UpsertMatchForGameService.new(
      user: denis,
      game: nil,
      actor: denis,
      mode: "singles",
      outcome: "win",
      opponent: opponent_one,
      played_at: played_at,
      score: "4-2",
      hours: 1.5,
      stats: { "opponent_ids" => [ opponent_one.id ] }
    ).call

    PlayerStatistics::UpsertMatchForGameService.new(
      user: denis,
      game: nil,
      actor: denis,
      mode: "singles",
      outcome: "loss",
      opponent: opponent_two,
      played_at: played_at,
      score: "2-4",
      hours: 1.0,
      stats: { "opponent_ids" => [ opponent_two.id ] }
    ).call

    matches = Match.where(user: denis, mode: "singles", played_at: played_at.to_date.all_day)
    assert_equal 2, matches.count
    assert_equal [ opponent_one.id, opponent_two.id ].sort, matches.map(&:opponent_id).sort
    assert_equal 2.5, denis.player_statistic.reload.singles_hours
  end

  test "game show prefills saved match into the stats form" do
    post session_url, params: { email: "stats_prefill_owner@example.com" }
    owner = User.find_by!(email: "stats_prefill_owner@example.com")
    participant = User.create!(email: "stats_prefill_participant@example.com", name: "Prefill Participant")
    game = Game.create!(court: courts(:one), user: owner, date: Date.yesterday, time: "10:00", with_coach: false)
    Participation.create!(game: game, user: participant, status: "approved")

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-4 6-7(5) 10-8",
          team_a_user_ids: [ owner.id ],
          team_b_user_ids: [ participant.id ],
          winner_team: "a"
        }
      }
    }

    get game_url(game)

    assert_response :success
    group_id = Match.where(game_id: game.id).first.stats.to_h.fetch("match_group_id")
    assert_includes response.body, group_id
    assert_includes response.body, 'value="6-4 6-7(5) 10-8"'
  end

  test "game show prefills saved match for a recurring game in the current cycle" do
    post session_url, params: { email: "stats_recurring_owner@example.com" }
    owner = User.find_by!(email: "stats_recurring_owner@example.com")
    participant = User.create!(email: "stats_recurring_participant@example.com", name: "Recurring Participant")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current - 14.days, time: "10:00", recurring: true, with_coach: false)
    Participation.create!(game: game, user: participant, status: "approved")

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-2 6-2",
          team_a_user_ids: [ owner.id ],
          team_b_user_ids: [ participant.id ],
          winner_team: "a"
        }
      }
    }

    match = Match.where(game_id: game.id).first
    assert_operator match.played_at, :>=, game.current_cycle_start

    get game_url(game)

    assert_response :success
    assert_includes response.body, match.stats.to_h.fetch("match_group_id")
    assert_includes response.body, 'value="6-2 6-2"'
  end

  test "score upsert with group_id updates the match instead of duplicating it" do
    post session_url, params: { email: "stats_edit_owner@example.com" }
    owner = User.find_by!(email: "stats_edit_owner@example.com")
    participant = User.create!(email: "stats_edit_participant@example.com", name: "Edit Participant")
    game = Game.create!(court: courts(:one), user: owner, date: Date.yesterday, time: "10:00", with_coach: false)
    Participation.create!(game: game, user: participant, status: "approved")

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          score: "6-4 6-4",
          team_a_user_ids: [ owner.id ],
          team_b_user_ids: [ participant.id ],
          winner_team: "a"
        }
      }
    }
    group_id = Match.where(game_id: game.id).first.stats.to_h.fetch("match_group_id")

    post game_player_statistics_url(game), params: {
      matches: {
        "0" => {
          group_id: group_id,
          score: "4-6 4-6",
          team_a_user_ids: [ owner.id ],
          team_b_user_ids: [ participant.id ],
          winner_team: "b"
        }
      }
    }

    assert_redirected_to game_path(game)
    assert_equal 2, Match.where(game_id: game.id).count
    assert_equal [ "4-6 4-6" ], Match.where(game_id: game.id).pluck(:score).uniq

    owner_stats = owner.player_statistic.reload
    assert_equal 1, owner_stats.singles_games
    assert_equal 0, owner_stats.singles_wins
    assert_equal 1, owner_stats.singles_losses
  end
end
