require "test_helper"

class Images::SvgRasterizerTest < ActiveSupport::TestCase
  SVG = %(<svg width="10" height="4" xmlns="http://www.w3.org/2000/svg"><rect width="10" height="4" fill="#000000"/></svg>).freeze

  test "renders svg that Active Storage blocks by default" do
    image = Images::SvgRasterizer.render(SVG, dpi: 72)

    assert_equal 10, image.width
    assert_equal 4, image.height
  end

  test "closes the svg loader back after the render" do
    Images::SvgRasterizer.render(SVG, dpi: 72)

    assert_raises(Vips::Error) { Vips::Image.svgload_buffer(SVG) }
  end
end
