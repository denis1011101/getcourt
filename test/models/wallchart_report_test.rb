require "test_helper"

class WallchartReportTest < ActiveSupport::TestCase
  EVENT = "wallchart_banner_viewed"

  test "counts an anonymous visitor even when an identified visit has a NULL visitor_token" do
    track(visitor_token: "anon-token")
    track(visitor_token: nil, user: users(:one))

    reach = WallchartReport.reach(EVENT)

    assert_equal 1, reach[:users]
    assert_equal 1, reach[:anon]
    assert_equal 2, reach[:people]
    assert_equal 2, reach[:total]
  end

  test "does not double-count a visitor whose token was later identified" do
    track(visitor_token: "shared-token")
    track(visitor_token: "shared-token", user: users(:one))

    reach = WallchartReport.reach(EVENT)

    assert_equal 1, reach[:users]
    assert_equal 0, reach[:anon]
    assert_equal 1, reach[:people]
    assert_equal 2, reach[:total]
  end

  test "classifies by the visit's user even when the event itself has no user" do
    visit = track(visitor_token: "member-token", user: users(:one))

    reach = WallchartReport.reach(EVENT)

    assert_nil visit.events.sole.user_id
    assert_equal({ users: 1, anon: 0, people: 1, total: 1 }, reach)
  end

  private

  # Mirrors Ahoy's write path: user_id lives on the visit; events keep user_id
  # NULL, which is exactly the case the report must classify correctly.
  def track(visitor_token:, user: nil)
    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.uuid,
      visitor_token: visitor_token,
      user: user,
      started_at: Time.current
    )
    Ahoy::Event.create!(visit: visit, name: EVENT, properties: {}, time: Time.current)
    visit
  end
end
