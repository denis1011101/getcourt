require "coverage"
require "fileutils"

Coverage.start(lines: true, branches: true) unless ENV["COVERAGE"] == "0"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Minitest.after_run do
  next if ENV["COVERAGE"] == "0"

  result = Coverage.result
  lines_data = result.values.filter_map { |file| file[:lines] if file.is_a?(Hash) }
  flat = lines_data.flatten.compact
  covered = flat.count { |v| v.positive? }
  total = flat.size
  percent = total.zero? ? 0.0 : ((covered.to_f / total) * 100).round(2)

  FileUtils.mkdir_p(Rails.root.join("coverage"))
  File.write(Rails.root.join("coverage", "summary.txt"), "Lines: #{percent}% (#{covered}/#{total})\n")
end

module ActiveSupport
  class TestCase
    workers = ENV["COVERAGE"] == "0" ? :number_of_processors : 1
    parallelize(workers: workers)
    fixtures :all
  end
end
