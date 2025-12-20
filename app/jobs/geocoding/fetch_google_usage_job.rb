require "google/cloud/monitoring"

module Geocoding
  class FetchGoogleUsageJob < ApplicationJob
    queue_as :default

    def perform
      project_id = ENV["GCP_PROJECT"]
      raise "GCP project not set (GCP_PROJECT / GOOGLE_CLOUD_PROJECT)" unless project_id

      period = (ENV["GOOGLE_GEOCODING_PERIOD"] || "hour").to_s.downcase
      filter = ENV["GEO_MONITORING_FILTER"]
      raise "Please set GEO_MONITORING_FILTER" if filter.to_s.empty?

      client = Google::Cloud::Monitoring::V3::MetricService::Client.new
      end_time = Time.now.utc
      start_time = period == "hour" ? end_time - 3600 : end_time - 24 * 3600

      interval = {
        start_time: { seconds: start_time.to_i, nanos: start_time.nsec },
        end_time:   { seconds: end_time.to_i,   nanos: end_time.nsec }
      }

      total = 0
      resp = client.list_time_series(
        name: "projects/#{project_id}",
        filter: filter,
        interval: interval,
        view: :FULL
      )

      resp.each do |ts|
        ts.points.each do |pt|
          val = nil
          if pt.value.respond_to?(:double_value) && !pt.value.double_value.nil?
            val = pt.value.double_value
          elsif pt.value.respond_to?(:int64_value) && !pt.value.int64_value.nil?
            val = pt.value.int64_value
          elsif pt.value.respond_to?(:distribution_value) && pt.value.distribution_value && pt.value.distribution_value.count
            val = pt.value.distribution_value.count
          end
          total += val.to_i if val
        end
      end

      key = if period == "hour"
              "geocoding:google:count:#{end_time.utc.strftime('%Y-%m-%d-%H')}"
            else
              "geocoding:google:count:#{end_time.utc.to_date}"
            end

      expiry = defined?(Geocoding::Quota) && defined?(Geocoding::Quota::EXPIRY) ? Geocoding::Quota::EXPIRY : (period == "hour" ? 2.hours : 2.days)
      Rails.cache.write(key, total, expires_in: expiry)

      Rails.logger.info("[Geocoding::FetchGoogleUsageJob] period=#{period} project=#{project_id} key=#{key} value=#{total} filter=#{filter.inspect}")
      total
    end
  end
end
