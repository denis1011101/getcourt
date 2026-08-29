# Пересобирает public/sitemap.xml — то же, что делает rake sitemap:generate.
#
# Solid Queue крутится внутри Puma (SOLID_QUEUE_IN_PUMA), поэтому файл пишется
# на ту же машину, что отдаёт статику. Адреса берутся из
# ApplicationHelper::SEO_PRIMARY_HOST, а не из окружения, так что задаче не
# нужны переменные, которые кроновая строка выставляла руками.
class GenerateSitemapJob < ApplicationJob
  queue_as :default

  # Путь инжектируется по той же причине, что и в SitemapGenerator: тесты идут
  # параллельно и не должны драться за общий public/sitemap.xml.
  def perform(path: SitemapGenerator.default_path)
    file = SitemapGenerator.generate!(path: path)
    Rails.logger.info "Wrote sitemap to #{file}"
    file
  end
end
