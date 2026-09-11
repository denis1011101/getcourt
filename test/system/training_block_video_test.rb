require "application_system_test_case"

class TrainingBlockVideoTest < ApplicationSystemTestCase
  # Ссылку на ролик вставляют как есть, часто без «https://». Поле поэтому
  # текстовое: с type="url" браузер отбраковывал бы такой адрес до отправки, и
  # серверная нормализация не успевала бы его дописать.
  test "a coach adds a video link without a scheme to a library block" do
    coach = User.create!(email: "system-video-coach@example.com", coach: true)

    visit new_session_path
    fill_in "Email", with: coach.email
    click_on "Enter"

    visit training_blocks_path
    assert_selector "input[name='training_block[video_url]'][type='text'][inputmode='url']"

    fill_in "training_block[title]", with: "Подача"
    fill_in "training_block[video_url]", with: "youtube.com/watch?v=dQw4w9WgXcQ"
    click_on I18n.t("training_blocks.create")

    block = coach.training_blocks.find_by!(title: "Подача")
    assert_equal "https://youtube.com/watch?v=dQw4w9WgXcQ", block.video_url
    assert_link "Video · YouTube", href: "https://youtube.com/watch?v=dQw4w9WgXcQ"
  end
end
