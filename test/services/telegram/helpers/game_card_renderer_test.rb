require "test_helper"
require "ostruct"

class Telegram::Helpers::GameCardRendererTest < ActiveSupport::TestCase
  test "renders a png card with game details" do
    user = User.new(id: 77, name: "Denis", telegram_username: "denis1011101")
    participations = ParticipationCollectionDouble.new(3)
    game = OpenStruct.new(
      id: 12,
      user_id: user.id,
      players_count: 4,
      court: OpenStruct.new(name: "Academy Court"),
      participations: participations,
      with_coach?: true,
      needs_coach?: false
    )

    path = nil

    stub_singleton(Telegram::Helpers::GameFormatting, :game_title, "Tennis") do
      stub_singleton(Telegram::Helpers::GameFormatting, :game_datetime, "2026-04-09 22:00") do
        stub_singleton(User, :find_by, user) do
          stub_singleton(Images::SvgRasterizer, :render_png, "\x89PNG\r\n\x1A\nfake".b) do
            path = Telegram::Helpers::GameCardRenderer.render(game, locale: :en)
          end
        end
      end
    end

    assert File.exist?(path)
    assert_equal "\x89PNG\r\n\x1A\n".b, File.binread(path, 8)
  ensure
    File.delete(path) if path.present? && File.exist?(path)
  end

  class ParticipationCollectionDouble
    def initialize(size)
      @size = size
    end

    def approved
      self
    end

    def size
      @size
    end
  end
end
