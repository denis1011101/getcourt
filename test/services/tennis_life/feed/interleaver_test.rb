require "test_helper"

class TennisLife::Feed::InterleaverTest < ActiveSupport::TestCase
  QUEUES = [
    [ "post", (1..30).to_a, 1.0 ],
    [ "match", (31..50).to_a, 1.0 ],
    [ "urgent", [ 51, 52 ], 3.0 ]
  ].freeze

  test "same seed produces the same complete sequence without duplicates" do
    first = TennisLife::Feed::Interleaver.new(QUEUES, seed: 123).call
    second = TennisLife::Feed::Interleaver.new(QUEUES, seed: 123).call

    assert_equal first, second
    assert_equal 52, first.size
    assert_equal first.size, first.uniq.size
  end

  test "different seeds produce different sequences" do
    first = TennisLife::Feed::Interleaver.new(QUEUES, seed: 123).call
    second = TennisLife::Feed::Interleaver.new(QUEUES, seed: 456).call

    assert_not_equal first, second
  end

  test "does not emit a third card of one kind while an alternative exists" do
    result = TennisLife::Feed::Interleaver.new(QUEUES, seed: 123).call
    last_alternative = result.rindex { |kind, _| kind != result.last.first }

    result.first(last_alternative + 1).each_cons(3) do |cards|
      assert_not_equal 1, cards.map(&:first).uniq.size
    end
  end

  test "rare weighted type is not buried in the last ten percent" do
    result = TennisLife::Feed::Interleaver.new(
      [ [ "common", (1..500).to_a, 1.0 ], [ "rare", [ 1 ], 3.0 ] ],
      seed: 123
    ).call

    assert_operator result.index([ "rare", 1 ]), :<, (result.size * 0.9)
  end
end
