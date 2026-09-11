require "test_helper"

class Games::SearchTest < ActiveSupport::TestCase
  # Порядок на странице игр: ближайшее сверху. Будущая игра сортируется по
  # своей дате — октябрьское утро не должно опережать сентябрьский вечер.
  test "upcoming games are ordered by their own date" do
    travel_to Time.zone.local(2026, 9, 10, 12, 0) do
      october = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 10, 5), time: "08:00")
      september = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 20), time: "20:00")

      assert_equal [ september.id, october.id ], ordered_ids(october, september)
    end
  end

  # А идущая серия — сверху: её ближайшее занятие не лежит в колонке date, там
  # дата, с которой серия когда-то началась.
  test "a series in progress comes before games later this month" do
    travel_to Time.zone.local(2026, 9, 10, 12, 0) do
      later = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 20), time: "08:00")
      series = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 8, 3), time: "20:00",
                            recurring: true)

      assert_equal [ series.id, later.id ], ordered_ids(later, series)
    end
  end

  private
    def ordered_ids(*games)
      Games::Search.new(scope: Game.where(id: games.map(&:id))).ordered.map(&:id)
    end
end
