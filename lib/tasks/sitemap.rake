namespace :sitemap do
  desc "Generate multilingual public/sitemap.xml"
  task generate: :environment do
    begin
      file = SitemapGenerator.generate!
      puts "Wrote sitemap to #{file}"
    rescue => e
      puts "Sitemap generation failed: #{e.class} #{e.message}"
      raise
    end
  end
end
