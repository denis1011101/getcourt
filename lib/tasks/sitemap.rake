namespace :sitemap do
  desc "Generate public/sitemap.xml (uses HOSTNAME or APP_HOST env var, default https://getcourt.co)"
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
