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

  test "a block the parser could not read in full does not pass as a late round" do
    text = <<~TEXT
      <b>ATP - SINGLES, US Open (USA), hard</b>
      12:00 - <i>Zverev A.</i> - : - <i>Shelton B.</i>
      #{(1..7).map { |i| "12:00 · Player #{i} vs Other #{i}" }.join("\n")}
    TEXT

    assert_nil board(text).highlight
    assert_equal 1, board(text).tournaments.first.matches.size
  end

  test "the earliest scheduled match wins by clock time, not by string" do
    text = <<~TEXT
      <b>ATP - SINGLES, US Open (USA), hard</b>
      12:00 - <i>Zverev A.</i> - : - <i>Shelton B.</i>
      9:00 - <i>Alcaraz C.</i> - : - <i>Sinner J.</i>
    TEXT

    assert_equal "Alcaraz C.", board(text).highlight.match.left.name
  end

  test "a snapshot keeps the tournaments it saw even after the gist changes" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    snapshot = Time.current.beginning_of_hour
    first = "<b>ATP - SINGLES, US Open (USA), hard</b>\n23:00 - <i>Zverev A.</i> - : - <i>Shelton B.</i>\n"
    later = "<b>WTA - SINGLES, Wuhan (China), hard</b>\n12:00 - <i>Gauff C.</i> - : - <i>Zheng Q.</i>\n"

    stub_singleton(TennisScoreboard::Fetcher, :raw_text, first) do
      assert_equal %w[us-open-usa], TennisScoreboard::Board.at(snapshot).tournaments.map(&:slug)
    end
    stub_singleton(TennisScoreboard::Fetcher, :raw_text, later) do
      assert_equal %w[us-open-usa], TennisScoreboard::Board.at(snapshot).tournaments.map(&:slug)
      assert_equal %w[wuhan-china], TennisScoreboard::Board.current.tournaments.map(&:slug)
      assert_equal %w[wuhan-china], TennisScoreboard::Board.at(snapshot + 1.hour).tournaments.map(&:slug)
    end
  ensure
    Rails.cache = previous_cache
  end

  test "a failed fetch is not frozen into the snapshot" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    snapshot = Time.current.beginning_of_hour
    text = "<b>ATP - SINGLES, US Open (USA), hard</b>\n23:00 - <i>Zverev A.</i> - : - <i>Shelton B.</i>\n"

    stub_singleton(TennisScoreboard::Fetcher, :raw_text, nil) do
      assert TennisScoreboard::Board.at(snapshot).empty?
    end
    stub_singleton(TennisScoreboard::Fetcher, :raw_text, text) do
      assert_equal %w[us-open-usa], TennisScoreboard::Board.at(snapshot).tournaments.map(&:slug)
    end
  ensure
    Rails.cache = previous_cache
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
