require "test_helper"
require "support/cache_helper"

class AiChatControllerTest < ActionDispatch::IntegrationTest
  include CacheHelper

  test "returns error for blank message" do
    post ai_chat_path, params: { message: "" }, as: :json
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "required"
  end

  test "returns reply from assistant" do
    fake_service = Object.new
    calls = []
    fake_service.define_singleton_method(:chat) do |message, **kwargs|
      calls << { message: message, history: kwargs[:history] }
      "Found @tennis_user and @coach_link in Moscow"
    end

    with_memory_cache do
      stub_singleton(Ai::AssistantService, :new, ->(_user) { fake_service }) do
        post ai_chat_path, params: { message: "Find me an opponent" }, as: :json
        assert_response :success
        assert_equal "Found @tennis_user and @coach_link in Moscow", response.parsed_body["reply"]
        assert_includes response.parsed_body["reply_html"], "https://t.me/tennis_user"
        assert_includes response.parsed_body["reply_html"], "https://t.me/coach_link"
      end
    end

    assert_equal [], calls.first[:history]
  end

  test "returns error json when assistant raises" do
    fake_service = Object.new
    fake_service.define_singleton_method(:chat) { |*| raise "boom" }

    stub_singleton(Ai::AssistantService, :new, ->(_user) { fake_service }) do
      post ai_chat_path, params: { message: "hello" }, as: :json
      assert_response :unprocessable_entity
      assert response.parsed_body["error"].present?
    end
  end

  test "passes cached history from previous messages" do
    fake_service = Object.new
    calls = []
    fake_service.define_singleton_method(:chat) do |message, **kwargs|
      calls << { message: message, history: kwargs[:history] }
      "Reply to #{message}"
    end

    with_memory_cache do
      stub_singleton(Ai::AssistantService, :new, ->(_user) { fake_service }) do
        post ai_chat_path, params: { message: "First" }, as: :json
        post ai_chat_path, params: { message: "Second" }, as: :json
      end
    end

    assert_equal [], calls[0][:history]
    assert_equal [
      { role: "user", content: "First" },
      { role: "assistant", content: "Reply to First" }
    ], calls[1][:history]
  end

  test "admin can record historical match stats without an existing game" do
    admin = User.create!(email: "admin_ai_stats@example.com", name: "Denis", telegram_username: "denis1011101", admin: true)
    opponent = User.create!(email: "opponent_ai_stats@example.com", name: "Aleksandr", telegram_username: "AleksanderKorobkin")

    result = Ai::Tools::RecordMatchStatsTool.new(admin).execute(
      game_date: "2026-04-08",
      score: "4:2",
      hours: "1.5",
      team_a: "@denis1011101",
      team_b: "@AleksanderKorobkin"
    )

    assert_equal true, result[:success]
    assert_equal "Historical match stats recorded successfully.", result[:message]
    assert_equal 1.5, result[:hours]

    matches = Match.where(mode: "singles", played_at: Date.new(2026, 4, 8).all_day).order(:id)
    assert_equal 2, matches.size
    assert_equal [ opponent.id ], Array(matches.find_by(user_id: admin.id).stats.to_h["opponent_ids"])
    assert_equal 1.5, admin.player_statistic.reload.singles_hours
    assert_equal 1.5, opponent.player_statistic.reload.singles_hours
  end

  test "admin can record several historical singles on the same day without overwriting previous ones" do
    admin = User.create!(email: "admin_multi_ai_stats@example.com", name: "Denis", telegram_username: "denis1011101", admin: true)
    opponent_one = User.create!(email: "opponent_one_ai_stats@example.com", name: "Aleksandr", telegram_username: "AleksanderKorobkin")
    opponent_two = User.create!(email: "opponent_two_ai_stats@example.com", name: "Keklil", telegram_username: "Keklil")

    tool = Ai::Tools::RecordMatchStatsTool.new(admin)
    first = tool.execute(game_date: "2026-04-08", score: "4:2", team_a: "@denis1011101", team_b: "@AleksanderKorobkin")
    second = tool.execute(game_date: "2026-04-08", score: "2:4", team_a: "@denis1011101", team_b: "@Keklil")

    assert_equal true, first[:success]
    assert_equal true, second[:success]
    assert_equal 4, Match.where(mode: "singles", played_at: Date.new(2026, 4, 8).all_day).count
    assert_equal 2, Match.where(user_id: admin.id, mode: "singles", played_at: Date.new(2026, 4, 8).all_day).count
  end

  test "admin can record historical doubles with hours" do
    admin = User.create!(email: "admin_doubles_ai_stats@example.com", name: "Denis", telegram_username: "denis1011101", admin: true)
    partner = User.create!(email: "partner_doubles_ai_stats@example.com", name: "Irina", telegram_username: "IrinaKarV")
    opponent_one = User.create!(email: "opponent_one_doubles_ai_stats@example.com", name: "Keklil", telegram_username: "Keklil")
    opponent_two = User.create!(email: "opponent_two_doubles_ai_stats@example.com", name: "Aleksandr", telegram_username: "AleksanderKorobkin")

    result = Ai::Tools::RecordMatchStatsTool.new(admin).execute(
      game_date: "2026-04-08",
      score: "6:2 6:3",
      hours: "2",
      team_a: "@denis1011101, @IrinaKarV",
      team_b: "@Keklil, @AleksanderKorobkin"
    )

    assert_equal true, result[:success]
    assert_equal "doubles", result[:mode]
    assert_equal 2.0, result[:hours]
    assert_equal 4, Match.where(mode: "doubles", played_at: Date.new(2026, 4, 8).all_day).count
    assert_equal 2.0, admin.player_statistic.reload.doubles_hours
    assert_equal 2.0, partner.player_statistic.reload.doubles_hours
    assert_equal 2.0, opponent_one.player_statistic.reload.doubles_hours
    assert_equal 2.0, opponent_two.player_statistic.reload.doubles_hours
  end

  test "non admin cannot record historical match stats without an existing game" do
    user = User.create!(email: "user_ai_stats@example.com", name: "Denis", telegram_username: "denis1011101")
    User.create!(email: "other_ai_stats@example.com", name: "Aleksandr", telegram_username: "AleksanderKorobkin")

    result = Ai::Tools::RecordMatchStatsTool.new(user).execute(
      game_date: "2026-04-08",
      score: "4:2",
      team_a: "@denis1011101",
      team_b: "@AleksanderKorobkin"
    )

    assert_includes result[:error], "No authorized game was found"
  end

  test "non admin cannot record historical doubles with hours without an existing game" do
    user = User.create!(email: "user_doubles_ai_stats@example.com", name: "Denis", telegram_username: "denis1011101")
    User.create!(email: "partner_doubles_ai_stats_blocked@example.com", name: "Irina", telegram_username: "IrinaKarV")
    User.create!(email: "opponent_one_doubles_ai_stats_blocked@example.com", name: "Keklil", telegram_username: "Keklil")
    User.create!(email: "opponent_two_doubles_ai_stats_blocked@example.com", name: "Aleksandr", telegram_username: "AleksanderKorobkin")

    result = Ai::Tools::RecordMatchStatsTool.new(user).execute(
      game_date: "2026-04-08",
      score: "6:2 6:3",
      hours: "2",
      team_a: "@denis1011101, @IrinaKarV",
      team_b: "@Keklil, @AleksanderKorobkin"
    )

    assert_includes result[:error], "No authorized game was found"
    assert_equal 0, Match.where(mode: "doubles", played_at: Date.new(2026, 4, 8).all_day).count
  end
end
