require "test_helper"

class PostDailySocialPostJobTest < ActiveJob::TestCase
  include CacheHelper

  test "hands the picked material to the publisher" do
    published = []

    stub_singleton(Social::DailyPlanner, :new, ->(*, **) { FakePlanner.new(content) }) do
      stub_singleton(Social, :publish, ->(argument) { published << argument }) do
        PostDailySocialPostJob.perform_now
      end
    end

    assert_equal [ content ], published
  end

  test "posts nothing when there is no fresh material" do
    published = []

    stub_singleton(Social::DailyPlanner, :new, ->(*, **) { FakePlanner.new(nil) }) do
      stub_singleton(Social, :publish, ->(argument) { published << argument }) do
        PostDailySocialPostJob.perform_now
      end
    end

    assert_empty published
  end

  private

  FakePlanner = Struct.new(:picked) do
    def pick = picked
  end

  def content
    @content ||= Social::Content::Daily.new(variant: "fact", subject: "total_hours", date: Date.current)
  end
end
