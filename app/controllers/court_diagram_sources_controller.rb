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

    # URL стабильный, а исходник меняется с деплоем: дай тут срок жизни — и
    # вернувшийся браузер до его конца будет исполнять старый Ruby рядом с новым
    # рантаймом, то есть ровно то расхождение, ради которого всё и затевалось.
    # Поэтому ревалидация обязательна: тело гоняется только когда ETag разошёлся.
    expires_in 0, public: true, must_revalidate: true
    return unless stale?(etag: source, public: true)

    render plain: source, content_type: "text/plain"
  end
end
