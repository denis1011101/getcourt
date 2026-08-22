require "test_helper"

class TrainingBlocksControllerTest < ActionDispatch::IntegrationTest
  test "the library page is closed to guests" do
    get training_blocks_url

    assert_redirected_to new_session_path
  end

  test "a coach sees their own blocks and not someone else's" do
    post session_url, params: { email: "library-coach@example.com" }
    coach = User.find_by!(email: "library-coach@example.com")
    coach.update!(coach: true)
    coach.training_blocks.create!(title: "Подача")
    stranger = User.create!(email: "library-stranger@example.com", coach: true)
    stranger.training_blocks.create!(title: "Чужой блок")

    get training_blocks_url

    assert_response :success
    assert_includes response.body, "Подача"
    assert_not_includes response.body, "Чужой блок"
  ensure
    stranger&.destroy
    coach&.destroy
  end

  test "a block is created, renamed and deleted from the library" do
    post session_url, params: { email: "library-crud@example.com" }
    coach = User.find_by!(email: "library-crud@example.com")
    coach.update!(coach: true)

    post training_blocks_url, params: { training_block: { title: "Разминка", duration_minutes: "15" } }

    assert_redirected_to training_blocks_path
    block = coach.training_blocks.sole
    assert_equal 15, block.duration_minutes

    patch training_block_url(block), params: { training_block: { title: "Разминка у сетки" } }

    assert_redirected_to training_blocks_path
    assert_equal "Разминка у сетки", block.reload.title

    assert_difference -> { coach.training_blocks.count }, -1 do
      delete training_block_url(block)
    end
  ensure
    coach&.destroy
  end

  test "a block without a title is rejected" do
    post session_url, params: { email: "library-invalid@example.com" }
    coach = User.find_by!(email: "library-invalid@example.com")
    coach.update!(coach: true)

    post training_blocks_url, params: { training_block: { title: "" } }

    assert_response :unprocessable_entity
    assert_equal 0, coach.training_blocks.count
  ensure
    coach&.destroy
  end

  test "someone else's block cannot be edited or deleted" do
    post session_url, params: { email: "library-thief@example.com" }
    thief = User.find_by!(email: "library-thief@example.com")
    stranger = User.create!(email: "library-victim@example.com", coach: true)
    block = stranger.training_blocks.create!(title: "Подача")

    patch training_block_url(block), params: { training_block: { title: "Взломано" } }
    assert_response :not_found

    delete training_block_url(block)
    assert_response :not_found

    assert_equal "Подача", block.reload.title
  ensure
    stranger&.destroy
    thief&.destroy
  end
end
