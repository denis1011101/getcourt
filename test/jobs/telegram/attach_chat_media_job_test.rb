require "test_helper"

class Telegram::AttachChatMediaJobTest < ActiveSupport::TestCase
  # 1x1 PNG: Active Storage опознаёт тип по содержимому, поэтому файл должен
  # быть настоящим.
  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=".freeze

  setup do
    @court = Court.create!(name: "Attach Court", city_name: "Yekaterinburg")
    @owner = User.create!(email: "attach_owner_#{SecureRandom.hex(4)}@example.com", name: "Owner", telegram_chat_id: 920_000_001)
    @game = Game.create!(court: @court, user: @owner, date: Date.current, kind: "game")
    @photo = { "kind" => "photo", "file_id" => "abc" }
  end

  teardown do
    @game&.destroy
    @owner&.destroy
    @court&.destroy
  end

  test "a photo from the chat lands on the game page, but not in the feed" do
    said = nil

    stub_singleton(Telegram::Api, :download_file, ->(_file_id) { [ png_file, "photo.jpg" ] }) do
      stub_singleton(Telegram::Api, :send_simple, ->(_chat_id, text, **_kw) { said = text }) do
        assert_difference -> { @game.game_media.count }, 1 do
          Telegram::AttachChatMediaJob.perform_now(@game.id, @owner.id, @photo, "вот корт")
        end
      end
    end

    medium = @game.game_media.last
    assert_equal @owner.id, medium.user_id
    assert_equal "вот корт", medium.title
    assert_not medium.show_in_feed
    assert medium.image?
    assert_equal Telegram::I18n.t(:chat_media_saved), said
  end

  # Потолок скачивания у Bot API — 20 МБ, и размер известен заранее: тянуть
  # такой файл незачем, но и промолчать нельзя.
  test "a file too big for the Bot API is answered instead of being fetched" do
    said = nil

    stub_singleton(Telegram::Api, :download_file, ->(*) { flunk "качать нечего" }) do
      stub_singleton(Telegram::Api, :send_simple, ->(_chat_id, text, **_kw) { said = text }) do
        assert_no_difference -> { @game.game_media.count } do
          Telegram::AttachChatMediaJob.perform_now(@game.id, @owner.id, @photo.merge("file_size" => 21.megabytes), nil)
        end
      end
    end

    assert_equal Telegram::I18n.t(:chat_media_too_big), said
  end

  test "an attachment over the game limit leaves no orphan file behind" do
    GameMedium::MAX_IMAGES_PER_GAME.times { |i| attach_image("shot#{i}.png") }
    said = nil

    stub_singleton(Telegram::Api, :download_file, ->(_file_id) { [ png_file, "photo.jpg" ] }) do
      stub_singleton(Telegram::Api, :send_simple, ->(_chat_id, text, **_kw) { said = text }) do
        assert_no_difference [ -> { @game.game_media.count }, -> { ActiveStorage::Blob.count } ] do
          Telegram::AttachChatMediaJob.perform_now(@game.id, @owner.id, @photo, nil)
        end
      end
    end

    assert_match(/не добавлен/, said.to_s)
  end

  test "someone who left the squad no longer attaches to the game" do
    stranger = User.create!(email: "attach_stranger_#{SecureRandom.hex(4)}@example.com", telegram_chat_id: 920_000_002)

    stub_singleton(Telegram::Api, :download_file, ->(*) { flunk "чужому качать нечего" }) do
      assert_no_difference -> { @game.game_media.count } do
        Telegram::AttachChatMediaJob.perform_now(@game.id, stranger.id, @photo, nil)
      end
    end
  ensure
    stranger&.destroy
  end

  private

  def png_file
    file = Tempfile.new([ "photo", ".png" ], binmode: true)
    file.write(Base64.decode64(SAMPLE_PNG))
    file.rewind
    file
  end

  def attach_image(filename)
    medium = @game.game_media.new(user: @owner)
    medium.file.attach(io: png_file, filename: filename)
    medium.save!
  end
end
