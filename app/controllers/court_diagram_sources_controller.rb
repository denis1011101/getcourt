# Отдаёт браузеру исходник TrainingBlock::Diagram — его исполняет ruby.wasm в
# редакторе схемы корта.
#
# Отдельным ответом, а не куском страницы: редакторов на странице библиотеки
# столько же, сколько блоков, а исходник на всех один и должен лечь в кеш
# браузера.
class CourtDiagramSourcesController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    source = TrainingBlock::Diagram::Source.call

    expires_in 1.hour, public: true
    return unless stale?(etag: source, public: true)

    render plain: source, content_type: "text/plain"
  end
end
