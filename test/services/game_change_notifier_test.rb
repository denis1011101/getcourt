require "test_helper"

class GameChangeNotifierTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @owner = users(:one)
    @participant = User.create!(email: "change-participant@example.com", notification_channel: "email", locale: "en")
    @game = Game.create!(court: courts(:one), user: @owner, date: Date.current + 3.days, time: "18:00")
    @game.participations.create!(user: @participant)
  end

  test "tells participants what changed and skips whoever made the edit" do
    @game.update!(time: "19:30")

    assert_enqueued_emails 1 do
      GameChangeNotifier.notify(game: @game, actor: @owner, changes: @game.saved_changes)
    end

    body = notification_body
    assert_includes body, "06:00 PM"
    assert_includes body, "07:30 PM"
    assert_includes body, "Time"
  end

  test "stays quiet when only bookkeeping fields changed" do
    @game.update!(urgent_player_search: true)

    assert_no_enqueued_emails do
      assert_not GameChangeNotifier.notify(game: @game, actor: @owner, changes: @game.saved_changes)
    end
  end

  test "does not notify the editor even when they are a participant" do
    @game.participations.create!(user: @owner)
    @game.update!(players_count: 2)

    assert_enqueued_emails 1 do
      GameChangeNotifier.notify(game: @game, actor: @owner, changes: @game.saved_changes)
    end
  end

  test "names the court instead of its id" do
    other_court = Court.create!(name: "Second court")
    @game.update!(court: other_court)

    assert_includes notification_body_for(@game.saved_changes), "Second court"
  end

  test "says the change covers the whole series for a weekly game" do
    @game.update!(recurring: true, time: "21:00")

    assert_includes notification_body_for(@game.saved_changes), "every upcoming date"
  end

  test "notifies the accepted coach as well" do
    coach = User.create!(email: "changed-game-coach@example.com", coach: true, notification_channel: "email", locale: "en")
    @game.update!(coach: coach, with_coach: true)
    @game.update!(coach_invitation_status: "accepted")

    @game.update!(time: "07:00")

    assert_enqueued_emails 2 do
      GameChangeNotifier.notify(game: @game, actor: @owner, changes: @game.saved_changes)
    end
  ensure
    coach&.destroy
  end

  private

  def notification_body
    notification_body_for(@game.saved_changes)
  end

  def notification_body_for(changes)
    notifier = GameChangeNotifier.new(game: @game, actor: @owner, changes: changes)
    notifier.send(:body_for, "en")
  end
end
