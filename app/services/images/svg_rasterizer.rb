# frozen_string_literal: true

module Images
  # Active Storage глушит небезопасные загрузчики libvips (`Vips.block_untrusted`),
  # чтобы через них нельзя было скормить librsvg чужой файл. Под нож попадает и наш
  # собственный рендер карточек, поэтому загрузчик SVG открываем точечно: под мьютексом
  # и только на время своего вызова, а сразу после — снова закрываем.
  module SvgRasterizer
    SVG_LOADER = "VipsForeignLoadSvg"
    LOCK = Mutex.new

    def self.render(svg, dpi:)
      require "vips" unless defined?(Vips::Image)

      LOCK.synchronize do
        Vips.block(SVG_LOADER, false)
        begin
          Vips::Image.svgload_buffer(svg, dpi: dpi)
        ensure
          Vips.block(SVG_LOADER, true)
        end
      end
    end
  end
end
