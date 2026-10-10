require "test_helper"

class OccurrenceSettingTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), recurring: true,
                         kind: "training", players_count: 4, prebooking_enabled: true)
    @date = Date.new(2026, 9, 14)
    @game.ensure_prebookings_for_dates([ @date ])
  end

  test "fewer players leaves fewer slots" do
    @game.occurrence_settings.create!(date: @date, players_count: 2)

    assert_equal [ 1, 2 ], @game.prebookings.where(date: @date).order(:slot_index).pluck(:slot_index)
  end

  # Совпадающее с серией не храним, а тренер у игры не бывает.
  test "kind and coach are stored only when they differ from the series" do
    same = @game.occurrence_settings.create!(date: @date, kind: "training", with_coach: false, players_count: 3)
    assert_equal [ nil, nil ], [ same.kind, same.with_coach ]

    same.update!(kind: "game", with_coach: true)
    assert_equal [ "game", nil ], [ same.kind, same.with_coach ]
    assert_not same.effective_with_coach?

    same.update!(kind: "training", with_coach: true)
    assert_equal [ nil, true ], [ same.kind, same.with_coach ]
  end

  test "shrinking keeps booked players and renumbers their slots" do
    @game.prebookings.find_by(date: @date, slot_index: 3).update!(user: users(:two))
    @game.occurrence_settings.create!(date: @date, players_count: 1)

    slots = @game.prebookings.where(date: @date)
    assert_equal [ [ 1, users(:two).id ] ], slots.pluck(:slot_index, :user_id)
  end

  test "cannot drop below players already booked" do
    @game.prebookings.where(date: @date, slot_index: [ 1, 2 ]).each_with_index { |pb, i| pb.update!(user: [ users(:one), users(:two) ][i]) }
    setting = @game.occurrence_settings.build(date: @date, players_count: 1)

    assert_not setting.valid?
    assert_equal 4, @game.prebookings.where(date: @date).count
  end

  test "removing the setting brings back the series slot count" do
    setting = @game.occurrence_settings.create!(date: @date, players_count: 2, court: courts(:two))
    setting.destroy!

    assert_equal 4, @game.prebookings.where(date: @date).count
    assert_equal 4, @game.prebooking_required_players(@date)
  end

  # Тренеры на дату: совпадающие с серией не храним, у игры их нет вовсе.
  test "date coaches are kept only for a training with a coach" do
    setting = @game.occurrence_settings.create!(date: @date, with_coach: true, coach: users(:two), guest_coach_name: "  Иван  ")
    assert_equal [ users(:two).id, "Иван" ], [ setting.coach_id, setting.guest_coach_name ]
    assert_equal [ users(:two).name, "Иван" ], setting.coach_names

    setting.update!(kind: "game")
    assert_not setting.coaches_set?
  end

  test "second coach cannot repeat the first" do
    setting = @game.occurrence_settings.build(date: @date, with_coach: true, coach: users(:two), second_coach: users(:two))

    assert_not setting.valid?
  end
end
