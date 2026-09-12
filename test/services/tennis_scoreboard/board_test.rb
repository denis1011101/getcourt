require "test_helper"

class TennisScoreboard::BoardTest < ActiveSupport::TestCase
  def board(text)
    TennisScoreboard::Board.new(text)
  end

  test "highlight prefers a live match on a major tournament" do
    text = <<~TEXT
      <b>ATP - SINGLES, US Open (USA), hard</b>
      23:00 - 🇩🇪 <i>Zverev A.</i> - : - 🇺🇸 <i>Shelton B.</i>

      <b>WTA - SINGLES, US Open (USA), hard</b>
      Set 1 - <i>Sabalenka A.</i> 0 : 0 🇰🇿 <i>Rybakina E.</i>
    TEXT

    highlight = board(text).highlight

    assert_equal "Sabalenka A.", highlight.match.left.name
    assert_equal "WTA", highlight.block.tour
    assert_equal "us-open-usa", board(text).lead.slug
  end

  test "the first week of a slam and non-major tournaments stay off the homepage" do
    early_round = (1..8).map { |i| "12:00 - <i>Player #{i}</i> - : - <i>Other #{i}</i>" }.join("\n")
    text = <<~TEXT
      <b>ATP - SINGLES, US Open (USA), hard</b>
      #{early_round}

      <b>WTA - SINGLES, Guadalajara (Mexico), hard</b>
      Set 2 - <i>Bucsa C.</i> 1 : 0 <i>Andreescu B.</i>
    TEXT

    assert_nil board(text).highlight
    # Без матча на главной ведущим остаётся первый турнир гиста.
    assert_equal "us-open-usa", board(text).lead.slug
  end

  test "finished matches are not highlighted and an empty board has no lead" do
    text = <<~TEXT
      <b>WTA - SINGLES, Wimbledon (Great Britain), grass</b>
      Finished - <i>Swiatek I.</i> 2 : 0 <i>Gauff C.</i>
    TEXT

    assert_nil board(text).highlight
    assert board("").empty?
    assert_nil board("").lead
  end
end
