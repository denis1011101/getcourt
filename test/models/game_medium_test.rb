require "test_helper"

class GameMediumTest < ActiveSupport::TestCase
  # 1x1 PNG — весит десятки байт, так что для проверки лимитов размер добиваем вручную.
  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze

  setup do
    @game = games(:feed_upcoming)
    @user = users(:one)
  end

  test "accepts a photo and knows it is an image" do
    medium = build_medium

    assert medium.save, medium.errors.full_messages.to_sentence
    assert medium.image?
    assert_not medium.video?
  end

  test "refuses a content type nobody asked for" do
    medium = build_medium(content_type: "application/pdf", filename: "sneaky.pdf")

    assert_not medium.valid?
    assert_includes medium.errors.attribute_names, :file
  end

  test "refuses a file over the size limit" do
    oversized = build_medium(bytes: "x" * (GameMedium::MAX_IMAGE_SIZE + 1))

    assert_not oversized.valid?

    # Видео тот же размер пропускает: у него свой, больший потолок.
    video = build_medium(content_type: "video/mp4", filename: "clip.mp4",
                         bytes: "x" * (GameMedium::MAX_IMAGE_SIZE + 1))
    assert video.valid?, video.errors.full_messages.to_sentence
  end

  test "caps how many photos one game can carry" do
    GameMedium::MAX_IMAGES_PER_GAME.times { |i| build_medium(filename: "shot-#{i}.png").save! }

    one_too_many = build_medium(filename: "extra.png")

    assert_not one_too_many.valid?
    assert_includes one_too_many.errors.attribute_names, :base
  end

  test "caps videos separately and more tightly than photos" do
    build_medium(content_type: "video/mp4", filename: "first.mp4").save!

    second = build_medium(content_type: "video/mp4", filename: "second.mp4")
    assert_not second.valid?

    # Фото при этом ещё можно: счётчики раздельные.
    assert build_medium(filename: "still-fine.png").valid?
  end

  test "hiding keeps the record but drops it out of the visible scope" do
    medium = build_medium
    medium.save!

    medium.hide!

    assert medium.hidden?
    assert_not_includes GameMedium.visible, medium
    assert_includes GameMedium.all, medium
  end

  test "goes away with its game" do
    build_medium.save!

    assert_difference -> { GameMedium.count }, -1 do
      @game.destroy
    end
  end

  private

  # identify: false — иначе Active Storage опознаёт тип по содержимому и заменяет
  # заявленный, а здесь проверяется как раз валидация заявленного типа.
  # В проде опознание работает и это к лучшему: переименованный в .png файл
  # получит настоящий content_type и споткнётся о ту же валидацию.
  def build_medium(content_type: "image/png", filename: "shot.png", bytes: nil)
    medium = GameMedium.new(game: @game, user: @user)
    medium.file.attach(
      io: StringIO.new(bytes || Base64.decode64(SAMPLE_PNG)),
      filename: filename,
      content_type: content_type,
      identify: false
    )
    medium
  end
end
