require "test_helper"

class MatchTest < ActiveSupport::TestCase
  setup do
    @user  = users(:one)
    @court = courts(:one)
  end

  test "a one-off game stays linked to its match" do
    game = Game.create!(user: @user, court: @court, date: Date.yesterday, recurring: false)
    match = build_match(game: game, played_at: Time.zone.yesterday.change(hour: 18))

    assert match.game_page_relevant?
  end

  test "a match without a game has nothing to link to" do
    assert_not build_match(game: nil, played_at: 1.day.ago).game_page_relevant?
  end

  test "deleting a one-off game takes its link away from the feed" do
    game = Game.create!(user: @user, court: @court, date: Date.yesterday, recurring: false)
    match = build_match(game: game, played_at: Time.zone.yesterday.change(hour: 18))
    match.save!

    assert match.game_page_relevant?, "пока игра жива, ссылка нужна"

    # has_many :matches, dependent: :nullify — статистика переживает удаление
    # игры, а вот ссылке вести уже некуда.
    game.destroy

    assert_nil match.reload.game_id
    assert_not match.game_page_relevant?
  end

  # Серия по понедельникам: до вечера четверга карточка держится за отыгранный
  # понедельник, потом переезжает на следующий.
  test "a recurring game drops the link once its cycle moves on" do
    game = Game.create!(user: @user, court: @court, date: Date.new(2026, 8, 31), time: "18:00", recurring: true)
    match = build_match(game: game, played_at: Time.zone.local(2026, 8, 31, 18, 0))

    travel_to Time.zone.local(2026, 9, 9, 12, 0) do
      assert_not match.game_page_relevant?,
                 "матч из прошлого цикла не должен вести на перезатёртую карточку игры"
    end
  end

  test "a recurring game keeps the link inside the current cycle" do
    game = Game.create!(user: @user, court: @court, date: Date.new(2026, 8, 31), time: "18:00", recurring: true)
    match = build_match(game: game, played_at: Time.zone.local(2026, 9, 7, 18, 0))

    travel_to Time.zone.local(2026, 9, 9, 12, 0) do
      assert match.game_page_relevant?
    end
  end

  private

  def build_match(game:, played_at:)
    Match.new(user: @user, game: game, mode: "singles", outcome: "win", played_at: played_at)
  end
end
