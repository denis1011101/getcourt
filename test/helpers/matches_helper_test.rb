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

  test "keeps the row's own side first when it sits in the second team" do
    denis = build_user("Denis")
    irina = build_user("Irina")

    match = Match.new(
      user: irina,
      user_id: irina.id,
      mode: "singles",
      outcome: "win",
      stats: { "team_a_ids" => [ denis.id ], "team_b_ids" => [ irina.id ] }
    )

    assert_equal [ "Irina", "Denis" ],
      match_feed_sides(match, names_by_id: match_names_by_id(match_related_user_ids(match)))
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

  test "the format badge counts the players actually on each side" do
    denis = build_user("Denis")
    katerina = build_user("Катерина")
    maxim = build_user("Максим")

    two_on_one = Match.new(user: denis, user_id: denis.id, mode: "doubles", outcome: "loss",
      stats: { "team_a_ids" => [ denis.id, katerina.id ], "team_b_ids" => [ maxim.id ] })
    with_guest = Match.new(user: denis, user_id: denis.id, mode: "doubles", outcome: "loss",
      stats: { "team_a_ids" => [ denis.id, katerina.id ], "team_b_ids" => [ maxim.id ], "team_b_guest_names" => [ "Саня Б" ] })
    legacy = Match.new(user: denis, user_id: denis.id, mode: "singles", outcome: "win", stats: {})

    assert_equal "2v1", match_format_label(two_on_one)
    assert_equal "2v2", match_format_label(with_guest)
    assert_equal "1v1", match_format_label(legacy)
  end

  private

  def build_user(name)
    User.create!(email: "helper-#{SecureRandom.hex(4)}@example.com", name: name)
  end
end
