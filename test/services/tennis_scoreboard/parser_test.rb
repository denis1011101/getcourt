require "test_helper"

class TennisScoreboard::ParserTest < ActiveSupport::TestCase
  SAMPLE = <<~TEXT
    <b>ATP - SINGLES, US Open (USA), hard</b>
    23:00 - 🇩🇪 <i>Zverev A.</i> - : - 🇺🇸 <i>Shelton B.</i>

    <b>WTA - SINGLES, US Open (USA), hard</b>
    Set 1 - <i>Sabalenka A.</i> 0 : 0 🇰🇿 <i>Rybakina E.</i>
    Finished - 🇵🇱 <i>Swiatek I.</i> 2 : 0 🇺🇸 <i>Gauff C.</i>
    something the parser does not understand

    <b>WTA - SINGLES, Guadalajara (Mexico), hard</b>
    21:00 - 🇪🇸 <i>Bucsa C.</i> - : - 🇨🇦 <i>Andreescu B.</i>
    21:00 - 🇫🇷 <i>Jacquemot E.</i> - : - <i>Samsonova L.</i>
  TEXT

  test "groups the blocks of one tournament and reads every match line" do
    tournaments = TennisScoreboard::Parser.parse(SAMPLE)

    assert_equal %w[us-open-usa guadalajara-mexico], tournaments.map(&:slug)

    us_open = tournaments.first
    assert_equal "US Open", us_open.name
    assert_equal "USA", us_open.country
    assert us_open.major?
    assert_equal %w[ATP WTA], us_open.blocks.map(&:tour)
    assert_equal [ "hard" ], us_open.blocks.map(&:surface).uniq

    scheduled, live, finished = us_open.matches
    assert scheduled.scheduled?
    assert_equal "23:00", scheduled.time
    assert_equal "🇩🇪", scheduled.left.flag
    assert_equal "Zverev A.", scheduled.left.name
    assert_equal "Shelton B.", scheduled.right.name
    assert_nil scheduled.score

    assert live.live?
    assert_equal "Set 1", live.label
    assert_nil live.left.flag
    assert_equal "0:0", live.score
    assert_equal "🇰🇿", live.right.flag

    assert_equal :finished, finished.status
    assert_equal "2:0", finished.score

    # Непонятная строка не теряется: она остаётся в сыром тексте карточки.
    assert_includes us_open.raw, "something the parser does not understand"
    assert_equal 3, us_open.matches.size
  end

  test "tournaments outside the major list are ordinary" do
    guadalajara = TennisScoreboard::Parser.parse(SAMPLE).last

    assert_not guadalajara.major?
    assert_equal "Mexico", guadalajara.country
    assert_nil guadalajara.matches.last.left.flag.presence && guadalajara.matches.last.right.flag
  end

  test "major list comes from config and matches case-insensitively" do
    tournaments = TennisScoreboard::Parser.parse(SAMPLE, major_names: [ "guadalajara" ])

    assert_equal [ false, true ], tournaments.map(&:major?)
    assert_includes TennisScoreboard::MajorTournaments.names, "Wimbledon"
  end

  test "blank text yields no tournaments" do
    assert_empty TennisScoreboard::Parser.parse("")
    assert_empty TennisScoreboard::Parser.parse("plain text without headers")
  end
end
