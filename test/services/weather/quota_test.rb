require "test_helper"

class Weather::QuotaTest < ActiveSupport::TestCase
  test "falls back to read and write when cache increment fails" do
    stub_singleton(Rails.cache, :increment, ->(*) { raise "cache unavailable" }) do
      assert_equal 1, Weather::Quota.increment!
    end
  end
end
