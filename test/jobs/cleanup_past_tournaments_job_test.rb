require "test_helper"

class CleanupPastTournamentsJobTest < ActiveJob::TestCase
  def create_user(tag)
    User.create!(email: "cleanup_#{tag}_#{SecureRandom.hex(4)}@example.com", name: "Cleanup #{tag}")
  end

  def create_tournament(user, overrides = {})
    Tournament.create!({ user: user, name: "T #{SecureRandom.hex(4)}", players_count: 4, format: "singles" }.merge(overrides))
  end

  test "removes tournament whose end_date is in the past" do
    user = create_user("past_end")
    t = create_tournament(user, end_date: Date.yesterday, start_date: Date.yesterday - 1)

    CleanupPastTournamentsJob.perform_now

    assert_nil Tournament.find_by(id: t.id)
  ensure
    t&.destroy
    user&.destroy
  end

  test "removes tournament with past start_date when end_date is absent" do
    user = create_user("past_start")
    t = create_tournament(user, start_date: Date.yesterday)

    CleanupPastTournamentsJob.perform_now

    assert_nil Tournament.find_by(id: t.id)
  ensure
    t&.destroy
    user&.destroy
  end

  test "keeps tournament whose end_date is today or future" do
    user = create_user("future")
    t = create_tournament(user, start_date: Date.current, end_date: Date.tomorrow)

    CleanupPastTournamentsJob.perform_now

    assert Tournament.find_by(id: t.id)
  ensure
    t&.destroy
    user&.destroy
  end

  test "keeps tournament with future start_date and no end_date" do
    user = create_user("future_start")
    t = create_tournament(user, start_date: Date.tomorrow)

    CleanupPastTournamentsJob.perform_now

    assert Tournament.find_by(id: t.id)
  ensure
    t&.destroy
    user&.destroy
  end

  test "removes dependent TournamentParticipant, TournamentCourt, TournamentDate records" do
    user = create_user("deps")
    participant_user = create_user("participant")
    court = Court.create!(name: "Dep Court #{SecureRandom.hex(4)}")
    t = create_tournament(user, end_date: Date.yesterday, start_date: Date.yesterday - 1)

    TournamentParticipant.create!(tournament: t, user: participant_user, name: participant_user.name)
    TournamentCourt.create!(tournament: t, court: court)
    TournamentDate.create!(tournament: t, date: Date.yesterday)

    tp_id = TournamentParticipant.where(tournament_id: t.id).pluck(:id)
    tc_id = TournamentCourt.where(tournament_id: t.id).pluck(:id)
    td_id = TournamentDate.where(tournament_id: t.id).pluck(:id)

    CleanupPastTournamentsJob.perform_now

    assert_empty TournamentParticipant.where(id: tp_id)
    assert_empty TournamentCourt.where(id: tc_id)
    assert_empty TournamentDate.where(id: td_id)
  ensure
    court&.destroy
    user&.destroy
    participant_user&.destroy
  end

  test "removes dependent tournament and game-linked records before destroying games" do
    organizer = create_user("graph_owner")
    p1 = create_user("graph_p1")
    p2 = create_user("graph_p2")
    actor = create_user("graph_actor")
    court = Court.create!(name: "Graph Court #{SecureRandom.hex(4)}")
    tournament = create_tournament(organizer, end_date: Date.yesterday, start_date: Date.yesterday - 1)
    tournament.courts << court

    tournament_match = TournamentMatch.create!(
      tournament: tournament,
      player_a: p1,
      player_b: p2,
      score: "6-4 6-3",
      result: "player_a",
      played_at: Time.current
    )

    game = Game.create!(
      tournament: tournament,
      court: court,
      user: organizer,
      date: Date.yesterday,
      sport: "Tennis",
      players_count: 2
    )

    participation = Participation.create!(game: game, user: p1, status: "approved")
    game_match = Match.create!(
      user: p1,
      opponent: p2,
      game: game,
      mode: "singles",
      outcome: "win",
      played_at: Time.current
    )
    stat_entry = PlayerStatisticEntry.create!(
      user: p1,
      actor: actor,
      game: game,
      source: "telegram",
      recorded_at: Time.current,
      data: { "score" => "6-4 6-3" }
    )

    CleanupPastTournamentsJob.perform_now

    assert_nil TournamentMatch.find_by(id: tournament_match.id)
    assert_nil Game.find_by(id: game.id)
    assert_nil Participation.find_by(id: participation.id)
    assert_nil game_match.reload.game_id, "match.game_id should be nullified to preserve history"
    assert_nil stat_entry.reload.game_id, "stat entry should survive with game_id nullified"
  ensure
    Match.where(id: game_match&.id).delete_all
    PlayerStatisticEntry.where(id: stat_entry&.id).delete_all
    court&.destroy
    organizer&.destroy
    p1&.destroy
    p2&.destroy
    actor&.destroy
  end
end
