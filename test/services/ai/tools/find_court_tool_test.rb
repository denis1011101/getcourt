require "test_helper"

class Ai::Tools::FindCourtToolTest < ActiveSupport::TestCase
  test "uses explicit city and sport filter" do
    requester = User.new(city_name: "Moscow")
    matching = Court.new(id: 42, name: "Center Court", city_name: "Moscow", sport: "tennis")
    relation = FakeCourtRelation.new([ matching ])

    stub_singleton(Court, :approved, relation) do
      result = Ai::Tools::FindCourtTool.new(requester).execute(city: "Moscow", sport: "tennis")

      assert_equal "Moscow", result[:city]
      assert_equal 1, result[:courts].size
      court = result[:courts][0]
      assert_equal matching.name, court[:name]
      assert_equal "tennis", court[:sport]
      assert_match %r{/courts/42\z}, court[:url]
      assert_equal [ [ "LOWER(city_name) LIKE LOWER(?)", "%Moscow%" ] ], relation.where_calls
      assert_equal [ { sport: "tennis" } ], relation.extra_where_calls
    end
  end

  test "falls back to user city and returns empty state" do
    requester = User.new(city_name: "Perm")
    relation = FakeCourtRelation.new([])

    stub_singleton(Court, :approved, relation) do
      result = Ai::Tools::FindCourtTool.new(requester).execute

      assert_equal "Perm", result[:city]
      assert_equal [], result[:courts]
      assert_equal "No courts found.", result[:message]
    end
  end

  test "returns error when city is unavailable" do
    requester = User.new

    result = Ai::Tools::FindCourtTool.new(requester).execute

    assert_includes result[:error], "City is required"
  end

  private

  class FakeCourtRelation
    attr_reader :where_calls, :extra_where_calls

    def initialize(records)
      @records = records
      @where_calls = []
      @extra_where_calls = []
    end

    def where(*args, **kwargs)
      if kwargs.any?
        @extra_where_calls << kwargs
      else
        @where_calls << args
      end
      self
    end

    def limit(_count)
      @records
    end
  end
end
