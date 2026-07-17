# Rack::Attack is inserted into the middleware stack by its railtie.
#
# Ahoy exposes public, unauthenticated endpoints (/ahoy/visits, /ahoy/events)
# when Ahoy.api is enabled. Throttle them per IP so a client can't flood the
# database with arbitrary events. See https://github.com/ankane/ahoy#throttling
class Rack::Attack
  throttle("ahoy/ip", limit: 20, period: 20.seconds) do |request|
    request.ip if request.path.start_with?("/ahoy")
  end
end
