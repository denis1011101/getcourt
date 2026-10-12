require "test_helper"

class PrebookingTest < ActiveSupport::TestCase
  test "user can only book one slot per game and date" do
    game = games(:one)
    date = Date.current + 6.weeks
    game.prebookings.create!(date: date, slot_index: 1, user: users(:one))
    duplicate = game.prebookings.build(date: date, slot_index: 2, user: users(:one))

    assert_not duplicate.valid?
    assert duplicate.errors.added?(:user_id, "can have only one booking for this game on the same date")
  end

  # Лимит 2, организатор записал троих и снял первого: третий переезжает в
  # освободившийся слот, и пустого места, куда звали бы записаться, нет.
  test "releasing a regular slot pulls in a player booked beyond the slots" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                        recurring: true, prebooking_enabled: true, players_count: 2)
    date = Date.new(2026, 9, 14)
    players = Array.new(3) { |i| User.create!(email: "release-#{i}@example.com") }
    slots = players.each_with_index.map { |player, i| game.prebookings.create!(date: date, slot_index: i + 1, user: player, status: "approved") }

    slots.first.release!

    assert_equal [ [ 1, players.last.id ], [ 2, players.second.id ] ], game.prebookings.where(date: date).order(:slot_index).pluck(:slot_index, :user_id)
  end

  test "releasing a slot beyond the slots removes it" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                        recurring: true, prebooking_enabled: true, players_count: 1)
    date = Date.new(2026, 9, 14)
    game.prebookings.create!(date: date, slot_index: 1, user: users(:one))
    extra = game.prebookings.create!(date: date, slot_index: 2, user: users(:two))

    extra.release!

    assert_not Prebooking.exists?(extra.id)
    assert_equal users(:one), game.prebookings.find_by!(date: date, slot_index: 1).user
  end
end
