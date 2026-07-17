# Unique-people counts for Wallchart '26 campaign events (used by wallchart:report).
#
# Counts people, not visits. A person is classified by the visit's user_id —
# Ahoy backfills ahoy_visits.user_id on sign-in while old ahoy_events.user_id
# stays NULL, so the visit is the reliable source. A visitor_token that appears
# in any identified visit belongs to that user and must not be counted again as
# anonymous.
class WallchartReport
  EVENT_NAMES = %w[
    wallchart_banner_viewed
    wallchart_banner_clicked
    wallchart_event_viewed
    wallchart_prediction_clicked
    wallchart_map_clicked
  ].freeze

  def self.reach(name)
    events = Ahoy::Event.where(name: name).joins(:visit)

    users = events.where.not(ahoy_visits: { user_id: nil })
                  .distinct.count("ahoy_visits.user_id")

    # NULL tokens must be excluded from the subquery: `NOT IN (..., NULL)`
    # matches no rows and would zero out the anonymous count entirely.
    identified_tokens = Ahoy::Visit.where.not(user_id: nil)
                                   .where.not(visitor_token: nil)
                                   .select(:visitor_token)
    anon = events.where(ahoy_visits: { user_id: nil })
                 .where.not(ahoy_visits: { visitor_token: identified_tokens })
                 .distinct.count("ahoy_visits.visitor_token")

    { users: users, anon: anon, people: users + anon, total: events.count }
  end
end
