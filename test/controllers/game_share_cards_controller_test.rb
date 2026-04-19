require "test_helper"
require "tempfile"

class GameShareCardsControllerTest < ActionDispatch::IntegrationTest
  test "renders generated game share card image" do
    file = Tempfile.new([ "game-card", ".png" ])
    file.binmode
    file.write("PNGDATA")
    file.close

    stub_singleton(Telegram::Helpers::GameCardRenderer, :render, ->(*) { file.path }) do
      get game_share_card_path(games(:one))
    end

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "PNGDATA", response.body
  ensure
    file&.close!
  end
end
