require "test_helper"

class Ai::Tools::FindOpponentToolTest < ActiveSupport::TestCase
  test "uses explicit city and skill filter" do
    requester = User.new(id: 99, city_name: "Moscow")
    matching = User.new(id: 2, city_name: "Moscow", skill_level: "beginner", telegram_username: "match_user")
    relation = FakeRelation.new([ matching ])
    fake_summary = { games: 5, wins: 3, win_pct: 60.0 }

    stub_singleton(User, :not_merged, ->(*) { relation }) do
      stub_singleton(PlayerStatistic, :summary_for, ->(_u) { fake_summary }) do
        result = Ai::Tools::FindOpponentTool.new(requester).execute(city: "Moscow", skill_level: "beginner")

        assert_equal "Moscow", result[:city]
        assert_equal 1, result[:opponents].size
        opponent = result[:opponents][0]
        assert_equal "@match_user", opponent[:name]
        assert_equal "beginner", opponent[:skill]
        assert_equal 5, opponent[:games]
        assert_equal 3, opponent[:wins]
        assert_equal 60.0, opponent[:win_pct]
        assert_equal [ [ "LOWER(city_name) LIKE LOWER(?)", "%Moscow%" ] ], relation.where_calls
        assert_equal [ { id: 99 } ], relation.where_not_calls
        assert_equal [ { coach: [ false, nil ] }, { skill_level: "beginner" } ], relation.extra_where_calls
      end
    end
  end

  test "falls back to user city and returns empty state" do
    requester = User.new(city_name: "Kazan")
    relation = FakeRelation.new([])

    stub_singleton(User, :not_merged, ->(*) { relation }) do
      result = Ai::Tools::FindOpponentTool.new(requester).execute

      assert_equal "Kazan", result[:city]
      assert_equal [], result[:opponents]
      assert_equal "No opponents found.", result[:message]
    end
  end

  test "returns error when city is unavailable" do
    requester = User.new

    result = Ai::Tools::FindOpponentTool.new(requester).execute

    assert_includes result[:error], "City is required"
  end

  private

  class FakeRelation
    attr_reader :where_calls, :where_not_calls, :extra_where_calls

    def initialize(records)
      @records = records
      @where_calls = []
      @where_not_calls = []
      @extra_where_calls = []
    end

    def where(*args, **kwargs)
      return self if args.empty? && kwargs.empty?

      if kwargs.any?
        @extra_where_calls << kwargs
      else
        @where_calls << args
      end
      self
    end

    def where_not(**kwargs)
      @where_not_calls << kwargs
      self
    end

    def not(**kwargs)
      where_not(**kwargs)
    end

    def where_not_proxy
      self
    end

    def limit(_count)
      @records
    end
  end
end
