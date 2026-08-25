require "test_helper"

class GameShareCardsControllerTest < ActionDispatch::IntegrationTest
  test "renders generated game share card image" do
    png_header = "\x89PNG\r\n\x1A\n".b

    stub_singleton(Games::ShareCardRenderer, :render_data, ->(*) { png_header }) do
      get game_share_card_path(games(:one))
    end

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal png_header, response.body.b
  end
end
