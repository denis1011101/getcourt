require "test_helper"

class Ai::Tools::FindCoachToolTest < ActiveSupport::TestCase
  test "finds coaches by city with bio" do
    requester = User.new(id: 99, city_name: "Moscow")
    coach = User.new(id: 2, city_name: "Moscow", coach: true, telegram_username: "great_coach", about_me: "10 years experience")
    relation = FakeRelation.new([ coach ])

    stub_singleton(User, :not_merged, ->(*) { relation }) do
      result = Ai::Tools::FindCoachTool.new(requester).execute(city: "Moscow")

      assert_equal "Moscow", result[:city]
      assert_equal 1, result[:coaches].size
      c = result[:coaches][0]
      assert_equal "@great_coach", c[:name]
      assert_equal "10 years experience", c[:bio]
    end
  end

  test "finds coaches without bio returns nil bio" do
    requester = User.new(id: 99, city_name: "Moscow")
    coach = User.new(id: 3, city_name: "Moscow", coach: true, telegram_username: "silent_coach", about_me: nil)
    relation = FakeRelation.new([ coach ])

    stub_singleton(User, :not_merged, ->(*) { relation }) do
      result = Ai::Tools::FindCoachTool.new(requester).execute(city: "Moscow")

      assert_equal 1, result[:coaches].size
      assert_nil result[:coaches][0][:bio]
    end
  end

  test "falls back to user city and returns empty state" do
    requester = User.new(city_name: "Kazan")
    relation = FakeRelation.new([])

    stub_singleton(User, :not_merged, ->(*) { relation }) do
      result = Ai::Tools::FindCoachTool.new(requester).execute

      assert_equal "Kazan", result[:city]
      assert_equal [], result[:coaches]
      assert_equal "No coaches found.", result[:message]
    end
  end

  test "returns error when city is unavailable" do
    requester = User.new

    result = Ai::Tools::FindCoachTool.new(requester).execute

    assert_includes result[:error], "City is required"
  end

  private

  class FakeRelation
    def initialize(records)
      @records = records
    end

    def where(*args, **kwargs)
      self
    end

    def where_not(**kwargs)
      self
    end

    def not(**kwargs)
      self
    end

    def limit(_count)
      @records
    end
  end
end
