require "test_helper"

class Images::SvgRasterizerTest < ActiveSupport::TestCase
  SVG = %(<svg width="10" height="4" xmlns="http://www.w3.org/2000/svg"><rect width="10" height="4" fill="#000000"/></svg>).freeze

  test "renders svg that this process is not allowed to load itself" do
    data = Images::SvgRasterizer.render_png(SVG, dpi: 72)

    assert_equal "\x89PNG\r\n\x1A\n".b, data[0, 8].b
  end

  test "leaves the svg loader blocked in the app process" do
    Images::SvgRasterizer.render_png(SVG, dpi: 72)

    assert_raises(Vips::Error) { Vips::Image.svgload_buffer(SVG) }
  end

  test "script lives outside the eager load paths" do
    eager_load_paths = Rails.application.config.eager_load_paths.map { |path| "#{path}/" }

    assert eager_load_paths.none? { |path| Images::SvgRasterizer::SCRIPT.start_with?(path) },
           "#{Images::SvgRasterizer::SCRIPT} would be executed by Zeitwerk on boot"
  end

  test "raises when the child cannot render" do
    assert_raises(Images::SvgRasterizer::Error) { Images::SvgRasterizer.render_png("not an svg at all", dpi: 72) }
  end
end
