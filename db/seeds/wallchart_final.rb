# Wallchart '26 promo: the World Cup 2026 final that the homepage banner links to.
#
# The homepage banner and the event-page promo only render while there is an
# active, upcoming featured match (see ApplicationHelper#wallchart_final?), so
# without this record the banner stays hidden.
#
# Idempotent: re-running db:seed reuses the existing final and refreshes its
# kickoff time and active flag (find_or_create_by would leave a stale record
# untouched). Manually edited player names are preserved.
#
# Setting it active deactivates any other active featured match
# (FeaturedMatch#deactivate_other_matches) — only one can be featured at a time.

WALLCHART_FINAL_LABEL = "World Cup 2026 Final".freeze
# Official kickoff: 19 Jul 2026, 15:00 in New York == 20 Jul 2026, 00:00 in
# Yekaterinburg. The app runs in Asia/Yekaterinburg, so state it in local time.
WALLCHART_FINAL_KICKOFF = Time.zone.local(2026, 7, 20, 0, 0)

final = FeaturedMatch.find_or_initialize_by(tournament_label: WALLCHART_FINAL_LABEL)
final.player_left_name = final.player_left_name.presence || "Finalist 1"
final.player_right_name = final.player_right_name.presence || "Finalist 2"
final.starts_at = WALLCHART_FINAL_KICKOFF
final.active = true
final.save!

puts "Wallchart final ready: /events/#{final.slug} (starts #{final.starts_at}, active=#{final.active})"
