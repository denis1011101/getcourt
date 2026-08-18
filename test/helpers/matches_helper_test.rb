require "test_helper"

class MatchesHelperTest < ActionView::TestCase
  test "names both doubles teams and the guests standing in them" do
    denis = build_user("Denis")
    maxim = build_user("Максим")
    irina = build_user("Irina")

    match = Match.new(
      user: denis,
      user_id: denis.id,
      mode: "doubles",
      outcome: "loss",
      score: "6-7(5) 3-4",
      stats: {
        "team_a_ids" => [ denis.id, maxim.id ],
        "team_b_ids" => [ irina.id ],
        "team_b_guest_names" => [ "Саня Б" ],
        "team_a_guest_names" => []
      }
    )

    names = match_names_by_id(match_related_user_ids(match))

    assert_equal [ "Denis + Максим", "Irina + Саня Б (guest)" ],
      match_feed_sides(match, names_by_id: names)
  end

  test "keeps the score's team first whichever row the card was built from" do
    denis = build_user("Denis")
    maxim = build_user("Максим")

    # One score string is stored on every row of the match and counts team A
    # first: Максим won it 6-3, so his name has to stay in front of it even on
    # the row that belongs to Denis.
    stats = { "team_a_ids" => [ maxim.id ], "team_b_ids" => [ denis.id ] }
    maxims_row = Match.new(user: maxim, user_id: maxim.id, mode: "singles", outcome: "win", score: "6-3", stats: stats)
    denis_row = Match.new(user: denis, user_id: denis.id, mode: "singles", outcome: "loss", score: "6-3", stats: stats)

    assert_equal [ "Максим", "Denis" ],
      match_feed_sides(maxims_row, names_by_id: match_names_by_id(match_related_user_ids(maxims_row)))
    assert_equal [ "Максим", "Denis" ],
      match_feed_sides(denis_row, names_by_id: match_names_by_id(match_related_user_ids(denis_row)))
  end

  test "names a guest opponent instead of calling the side anonymous" do
    romaus = build_user("Romaus")

    match = Match.new(
      user: romaus,
      user_id: romaus.id,
      mode: "singles",
      outcome: "loss",
      stats: {
        "team_a_ids" => [ romaus.id ],
        "team_b_ids" => [],
        "opponent_ids" => [],
        "team_b_guest_names" => [ "Andrey" ]
      }
    )

    assert_equal [ "Romaus", "Andrey (guest)" ],
      match_feed_sides(match, names_by_id: match_names_by_id(match_related_user_ids(match)))
  end

  test "falls back to the anonymous label when the other side is empty" do
    romaus = build_user("Romaus")
    match = Match.new(user: romaus, user_id: romaus.id, mode: "singles", outcome: "loss", stats: {})

    assert_equal [ "Romaus", I18n.t("tennis_life.anonymous_player") ],
      match_feed_sides(match, names_by_id: match_names_by_id(match_related_user_ids(match)))
  end

  test "reads the older rows that carry a partner and an opponent" do
    denis = build_user("Denis")
    maxim = build_user("Максим")
    irina = build_user("Irina")

    match = Match.new(
      user: denis,
      user_id: denis.id,
      opponent: irina,
      opponent_id: irina.id,
      mode: "doubles",
      outcome: "win",
      stats: { "partner_id" => maxim.id }
    )

    assert_equal [ "Denis + Максим", "Irina" ],
      match_feed_sides(match, names_by_id: match_names_by_id(match_related_user_ids(match)))
  end

  private

  def build_user(name)
    User.create!(email: "helper-#{SecureRandom.hex(4)}@example.com", name: name)
  end
end
