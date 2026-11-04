require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @author = User.create!(name: "Content Author", email: "author-report-test@example.com")
    @reporter = User.create!(name: "Reporter User", email: "reporter-report-test@example.com")
    @outsider = User.create!(name: "Outsider User", email: "outsider-report-test@example.com")
    @game = games(:feed_upcoming)
    @shared_block = TrainingBlock.create!(user: @author, title: "Shared Drill", description: "Drill description", shared: true)
    @private_block = TrainingBlock.create!(user: @author, title: "Private Drill", description: "Private", shared: false)
    @other_block = TrainingBlock.create!(user: @author, title: "Other Drill", description: "Other", shared: false)
  end

  test "returns 422 for unallowed target type" do
    post reports_path, params: { target_type: "UnknownModel", target_id: 123 }, as: :json
    assert_response :unprocessable_entity
    assert_equal "Invalid target type", response.parsed_body["error"]
  end

  test "returns 404 when target does not exist" do
    post reports_path, params: { target_type: "TrainingBlock", target_id: 999_999 }, as: :json
    assert_response :not_found
    assert_equal "Target not found", response.parsed_body["error"]
  end

  test "returns 404 for unattached private training block from guest" do
    assert_not @private_block.shared?
    assert_empty @private_block.games

    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**_args) { true }) do
      post reports_path, params: {
        target_type: "TrainingBlock",
        target_id: @private_block.id,
        reason: "Inappropriate"
      }, as: :json

      assert_response :not_found
      assert_equal "Target not found", response.parsed_body["error"]
    end
  end

  test "returns 404 for unattached private training block from signed in outsider" do
    sign_in_as @outsider
    assert_not @private_block.shared?
    assert_empty @private_block.games

    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**_args) { true }) do
      post reports_path, params: {
        target_type: "TrainingBlock",
        target_id: @private_block.id,
        reason: "Inappropriate"
      }, as: :json

      assert_response :not_found
      assert_equal "Target not found", response.parsed_body["error"]
    end
  end

  test "returns 404 when proposal contains another block and does not match exact id" do
    # Ensure collision where other_block ID contains private_block ID as substring
    collision_id = (@private_block.id * 10) + 7
    @other_block.update_column(:id, collision_id)

    training_game = Game.create!(court: courts(:one), user: @author, date: Date.tomorrow, time: "18:00", kind: "training")
    training_game.training_plan_proposals.create!(
      user: @author,
      training_block_ids: [ collision_id ],
      mode: "direct",
      status: "pending"
    )

    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**_args) { true }) do
      post reports_path, params: {
        target_type: "TrainingBlock",
        target_id: @private_block.id,
        reason: "Inappropriate"
      }, as: :json

      assert_response :not_found
      assert_equal "Target not found", response.parsed_body["error"]
    end
  end

  test "reports private training block when included in proposal" do
    training_game = Game.create!(court: courts(:one), user: @author, date: Date.tomorrow, time: "18:00", kind: "training")
    training_game.training_plan_proposals.create!(
      user: @author,
      training_block_ids: [ @private_block.id ],
      mode: "direct",
      status: "pending"
    )

    notified = false
    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**args) {
      notified = true
      assert_equal "TrainingBlock", args[:target_type]
      assert_equal @private_block.id, args[:target_id]
      true
    }) do
      post reports_path, params: {
        target_type: "TrainingBlock",
        target_id: @private_block.id,
        reason: "Inappropriate"
      }, as: :json

      assert_response :success
      assert response.parsed_body["ok"]
    end

    assert notified
  end

  test "reports private training block attached to a game" do
    @private_block.games << @game

    notified = false
    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**args) {
      notified = true
      assert_equal "TrainingBlock", args[:target_type]
      assert_equal @private_block.id, args[:target_id]
      true
    }) do
      post reports_path, params: {
        target_type: "TrainingBlock",
        target_id: @private_block.id,
        reason: "Inappropriate"
      }, as: :json

      assert_response :success
      assert response.parsed_body["ok"]
    end

    assert notified
  end

  test "reports shared training block successfully as signed in user" do
    sign_in_as @reporter

    notified = false
    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**args) {
      notified = true
      assert_equal "TrainingBlock", args[:target_type]
      assert_equal @shared_block.id, args[:target_id]
      assert_includes args[:author], "Content Author"
      assert_includes args[:reporter], "Reporter User"
      assert_equal "Spam content", args[:reason]
      true
    }) do
      post reports_path, params: {
        target_type: "TrainingBlock",
        target_id: @shared_block.id,
        reason: "Spam content"
      }, as: :json

      assert_response :success
      assert response.parsed_body["ok"]
      assert_equal I18n.t("ugc.report_success"), response.parsed_body["message"]
    end

    assert notified, "Expected Telegram::AdminNotifier.notify_ugc_report to be called"
  end

  test "reports as guest user" do
    notified = false
    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**args) {
      notified = true
      assert_includes args[:reporter], "Guest"
      true
    }) do
      post reports_path, params: {
        target_type: "TrainingBlock",
        target_id: @shared_block.id,
        reason: "Inappropriate"
      }, as: :json

      assert_response :success
      assert response.parsed_body["ok"]
    end

    assert notified
  end

  test "reports user when blocking" do
    notified = false
    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**args) {
      notified = true
      assert_equal "User", args[:target_type]
      assert_equal @author.id, args[:target_id]
      true
    }) do
      post reports_path, params: {
        target_type: "User",
        target_id: @author.id,
        reason: "User blocked by viewer"
      }, as: :json

      assert_response :success
    end

    assert notified
  end

  test "returns 503 service unavailable when telegram delivery fails" do
    stub_singleton(Telegram::AdminNotifier, :notify_ugc_report, ->(**_args) { false }) do
      post reports_path, params: {
        target_type: "TrainingBlock",
        target_id: @shared_block.id,
        reason: "Inappropriate"
      }, as: :json

      assert_response :service_unavailable
      assert_not response.parsed_body["ok"]
      assert_equal I18n.t("ugc.report_failed"), response.parsed_body["error"]
    end
  end

  test "returns 503 when telegram api rejects message with ok false hash" do
    stub_singleton(Telegram::AdminNotifier, :admin_recipient, -> { { chat_id: "123", locale: "en" } }) do
      stub_singleton(Telegram::Api, :send_simple, ->(*_args, **_kwargs) { { "ok" => false, "error_code" => 429 } }) do
        post reports_path, params: {
          target_type: "TrainingBlock",
          target_id: @shared_block.id,
          reason: "Inappropriate"
        }, as: :json

        assert_response :service_unavailable
        assert_not response.parsed_body["ok"]
        assert_equal I18n.t("ugc.report_failed"), response.parsed_body["error"]
      end
    end
  end

  private

  def sign_in_as(user)
    post session_url, params: { email: user.email }
  end
end
