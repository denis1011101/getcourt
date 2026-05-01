require "coverage"
require "etc"
require "fileutils"

COVERAGE_ENABLED = ENV["COVERAGE"] != "0"
COVERAGE_RUN_ID = ENV["COVERAGE_RUN_ID"] ||= "#{Process.pid}-#{Time.now.to_i}"
EXPECTED_COVERAGE_WORKERS = ENV.fetch("PARALLEL_WORKERS", Etc.nprocessors).to_i

Coverage.start(lines: true, branches: true) if COVERAGE_ENABLED

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
Dir[Rails.root.join("test/support/**/*.rb")].sort.each { |file| require file }

Minitest.after_run do
  next unless COVERAGE_ENABLED

  raw_dir = Rails.root.join("coverage", "raw")
  lock_path = Rails.root.join("coverage", ".coverage_merge.lock")
  FileUtils.mkdir_p(raw_dir)

  raw_path = raw_dir.join("#{COVERAGE_RUN_ID}-#{Process.pid}.dump")
  File.binwrite(raw_path, Marshal.dump(Coverage.result))

  File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
    lock.flock(File::LOCK_EX)

    run_files = Dir[raw_dir.join("#{COVERAGE_RUN_ID}-*.dump")]
    merged = {}

    run_files.each do |path|
      data = Marshal.load(File.binread(path))

      data.each do |file, payload|
        next unless payload.is_a?(Hash)

        entry = (merged[file] ||= { lines: [], branches: {} })

        lines = payload[:lines] || []
        max_len = [ entry[:lines].length, lines.length ].max
        entry[:lines] = Array.new(max_len) do |idx|
          a = entry[:lines][idx]
          b = lines[idx]
          if a.nil? || b.nil?
            a || b
          else
            a + b
          end
        end

        branches = payload[:branches] || {}
        branches.each do |branch_key, value|
          current = entry[:branches][branch_key]
          entry[:branches][branch_key] = current.nil? ? value : current + value
        end
      end
    end

    covered = 0
    total = 0

    merged.each_value do |payload|
      payload[:lines].compact.each do |hits|
        total += 1
        covered += 1 if hits.positive?
      end
    end

    percent = total.zero? ? 0.0 : ((covered.to_f / total) * 100).round(2)
    workers_count = [ run_files.size, EXPECTED_COVERAGE_WORKERS ].min

    summary = <<~TXT
      Lines: #{percent}% (#{covered}/#{total})
      Workers merged: #{workers_count}
    TXT

    File.write(Rails.root.join("coverage", "summary.txt"), summary)
  end
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include StubHelper if defined?(StubHelper)

    setup { I18n.locale = I18n.default_locale }
  end
end
