class Ahoy::Store < Ahoy::DatabaseStore
end

# Banner impressions/clicks are tracked from JavaScript (ahoy.js), which posts
# to /ahoy/events. This requires the API.
Ahoy.api = true

# Only create a visit server-side when we track an event without an existing JS
# visit (e.g. a direct visit to the event page). Avoids double-counting visits.
Ahoy.server_side_visits = :when_needed

# Privacy: no geocoding, and mask the last octet of IP addresses.
Ahoy.geocode = false
Ahoy.mask_ips = true

# Bots are excluded by default (Ahoy.track_bots = false).
