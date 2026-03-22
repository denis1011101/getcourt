require "test_helper"

class CleanupPastOneOffGamesJobTest < ActiveJob::TestCase
  def setup
    @user  = users(:one)
    @court = courts(:one)
  end

  test "destroys a past one-off game with no associated records" do
    game = Game.create!(user: @user, court: @court, date: Date.yesterday, recurring: false)

    CleanupPastOneOffGamesJob.perform_now

    assert_nil Game.find_by(id: game.id)
  end

  test "destroys a past one-off game that has matches, nullifying game_id on those matches" do
    game = Game.create!(user: @user, court: @court, date: Date.yesterday, recurring: false)
    match = Match.create!(
      user: @user,
      game: game,
      mode: "singles",
      outcome: "win",
      played_at: Date.yesterday
    )

    CleanupPastOneOffGamesJob.perform_now

    assert_nil Game.find_by(id: game.id), "game should be destroyed"
    assert_nil match.reload.game_id, "match.game_id should be nullified"
  end

  test "does not destroy a past recurring game" do
    game = Game.create!(user: @user, court: @court, date: Date.yesterday, recurring: true)

    CleanupPastOneOffGamesJob.perform_now

    assert_not_nil Game.find_by(id: game.id)
  ensure
    game&.destroy
  end

  test "does not destroy a future one-off game" do
    game = Game.create!(user: @user, court: @court, date: Date.tomorrow, recurring: false)

    CleanupPastOneOffGamesJob.perform_now

    assert_not_nil Game.find_by(id: game.id)
  ensure
    game&.destroy
  end

  test "destroys participations before removing the game" do
    game = Game.create!(user: @user, court: @court, date: Date.yesterday, recurring: false)
    game.participations.create!(user: @user)

    CleanupPastOneOffGamesJob.perform_now

    assert_nil Game.find_by(id: game.id)
    assert_equal 0, Participation.where(game_id: game.id).count
  end
end
