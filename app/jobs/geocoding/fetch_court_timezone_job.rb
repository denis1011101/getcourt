class Geocoding::FetchCourtTimezoneJob < ApplicationJob
  queue_as :default

  def perform(court_id)
    court = Court.find_by(id: court_id)
    court&.fetch_and_set_timezone!
  end
end
