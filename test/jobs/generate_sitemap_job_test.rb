require "test_helper"

class GenerateSitemapJobTest < ActiveSupport::TestCase
  # Свой файл на процесс: набор идёт параллельно, общий public/sitemap.xml
  # воркеры затирали бы друг у друга.
  setup do
    @sitemap_file = Rails.root.join("tmp", "sitemap-job-test-#{Process.pid}.xml")
  end

  teardown do
    File.delete(@sitemap_file) if File.exist?(@sitemap_file)
  end

  test "writes the sitemap" do
    GenerateSitemapJob.perform_now(path: @sitemap_file)

    assert_path_exists @sitemap_file
    assert_includes File.read(@sitemap_file), "https://getcourt.co/"
  end

  test "is registered as a recurring production task" do
    tasks = YAML.load_file(Rails.root.join("config", "recurring.yml")).fetch("production")

    assert_equal "GenerateSitemapJob", tasks.dig("generate_sitemap", "class")
    assert_equal "at 7am every day", tasks.dig("generate_sitemap", "schedule")
  end
end
