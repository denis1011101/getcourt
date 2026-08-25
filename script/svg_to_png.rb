# frozen_string_literal: true

# Отдельный процесс: читает SVG из stdin, пишет PNG в stdout.
#
# Живёт в `script/`, а не в `lib/`: `lib` целиком в eager_load_paths, и Zeitwerk
# выполнил бы этот файл при загрузке приложения — с чужим ARGV и без stdin.
#
# Внутри приложения этого сделать нельзя. Active Storage глушит загрузчики libvips
# (`Vips.block_untrusted`), чтобы librsvg не разбирал чужие файлы, а снимать блокировку
# на лету — значит открыть окно, в которое соседний поток веб-процесса успеет прогнать
# через тот же загрузчик пользовательскую картинку. Здесь Rails не загружается, блокировки
# нет, и рендерится только наш собственный, заведомо доверенный SVG.
require "vips"

dpi = Integer(ARGV[0] || 72)
svg = $stdin.binmode.read

$stdout.binmode.write(Vips::Image.svgload_buffer(svg, dpi: dpi).write_to_buffer(".png"))
