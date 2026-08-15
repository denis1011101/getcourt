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

  test "a recurring game drops the link once its cycle moves on" do
    game = Game.create!(user: @user, court: @court, date: 3.weeks.ago.to_date, recurring: true)
    # Пятничный ResetParticipationsJob уже перевёл игру на ближайшее вхождение.
    game.mark_participations_reset!(game.next_date)
    played_at = (game.next_date - 2.weeks).in_time_zone.change(hour: 18)

    match = build_match(game: game.reload, played_at: played_at)

    assert_not match.game_page_relevant?,
               "матч из прошлого цикла не должен вести на перезатёртую карточку игры"
  end

  test "a recurring game keeps the link inside the current cycle" do
    game = Game.create!(user: @user, court: @court, date: 3.weeks.ago.to_date, recurring: true)
    previous = game.next_date - 1.week
    game.mark_participations_reset!(previous)
    match = build_match(game: game.reload, played_at: previous.in_time_zone.change(hour: 18))

    assert match.game_page_relevant?
  end

  private

  def build_match(game:, played_at:)
    Match.new(user: @user, game: game, mode: "singles", outcome: "win", played_at: played_at)
  end
end
