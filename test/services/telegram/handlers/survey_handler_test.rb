require "test_helper"
require "support/cache_helper"

class Telegram::Handlers::SurveyHandlerTest < ActiveSupport::TestCase
  include Telegram::Helpers
  include CacheHelper

  CHAT = "survey_test_#{SecureRandom.hex(4)}".freeze

  def setup
    @api_log = Hash.new { |h, k| h[k] = [] }
    log = @api_log
    @orig_api_methods = {}
    %i[send_simple send_with_buttons send_force_reply answer_callback].each do |m|
      sc = Telegram::Api.singleton_class
      @orig_api_methods[m] = sc.instance_method(m) if sc.method_defined?(m) || sc.private_method_defined?(m)
      sc.define_method(m) { |*a, **_kw| log[m] << a }
    end
  end

  def teardown
    sc = Telegram::Api.singleton_class
    %i[send_simple send_with_buttons send_force_reply answer_callback].each do |m|
      if @orig_api_methods&.key?(m) && @orig_api_methods[m]
        sc.define_method(m, @orig_api_methods[m])
      else
        sc.remove_method(m) rescue nil
      end
    end
  end

  def cb(data, chat_id: CHAT)
    { "data" => data, "id" => "cb1", "from" => { "id" => chat_id },
      "message" => { "chat" => { "id" => chat_id } } }
  end

  # ---- start ---------------------------------------------------------------

  test "start sends greeting and language picker" do
    with_memory_cache do
      Telegram::Handlers::SurveyHandler.start(CHAT)
    end
    assert_equal 1, @api_log[:send_simple].size
    assert_equal 1, @api_log[:send_with_buttons].size
  end

  test "start initialises conversation state in cache" do
    with_memory_cache do
      Telegram::Handlers::SurveyHandler.start(CHAT)
      assert Conversation.get(CHAT).key?("created_at")
    end
  end

  # ---- survey_lang:set -----------------------------------------------------

  test "survey_lang:set saves language and sends ask_city in chosen locale" do
    with_memory_cache do
      Conversation.start(CHAT)
      Telegram::Handlers::SurveyHandler.handle_callback(cb("survey_lang:set:en"))
      state = Conversation.get(CHAT)
      assert_equal "en",       state["language"]
      assert_equal "ask_city", state["step"]
      assert_equal 1, @api_log[:send_force_reply].size
      assert_includes @api_log[:send_force_reply].first[1], "city"
    end
  end

  # ---- survey_lang:skip ----------------------------------------------------

  test "survey_lang:skip sets step to ask_city" do
    with_memory_cache do
      Conversation.start(CHAT)
      Telegram::Handlers::SurveyHandler.handle_callback(cb("survey_lang:skip"))
      assert_equal "ask_city", Conversation.get(CHAT)["step"]
      assert_equal 1, @api_log[:send_force_reply].size
    end
  end

  # ---- handle_message: ask_city --------------------------------------------

  test "handle_message at ask_city stores city and moves to ask_sports" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_city", "language" => "en")
      Telegram::Handlers::SurveyHandler.handle_message(CHAT, "Moscow")
      state = Conversation.get(CHAT)
      assert_equal "Moscow",     state["city"]
      assert_equal "ask_sports", state["step"]
      assert_equal 1, @api_log[:send_with_buttons].size
    end
  end

  test "handle_message at ask_city with 'skip' stores nil city" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_city", "language" => "en")
      Telegram::Handlers::SurveyHandler.handle_message(CHAT, "skip")
      assert_nil     Conversation.get(CHAT)["city"]
      assert_equal "ask_sports", Conversation.get(CHAT)["step"]
    end
  end

  test "handle_message uses conversation language for locale" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_city", "language" => "ru")
      Telegram::Handlers::SurveyHandler.handle_message(CHAT, "Казань")
      assert_equal 1, @api_log[:send_with_buttons].size
    end
  end

  # ---- sport:toggle --------------------------------------------------------

  test "sport:toggle adds sport to selected_sports" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_sports", "language" => "en")
      Telegram::Handlers::SurveyHandler.handle_callback(cb("sport:toggle:tennis"))
      assert_includes Conversation.get(CHAT)["selected_sports"], "tennis"
    end
  end

  test "sport:toggle removes sport if already selected" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_sports", "language" => "en", "selected_sports" => ["tennis"])
      Telegram::Handlers::SurveyHandler.handle_callback(cb("sport:toggle:tennis"))
      assert_not_includes Conversation.get(CHAT)["selected_sports"], "tennis"
    end
  end

  # ---- sport:skip_all ------------------------------------------------------

  test "sport:skip_all clears sports and moves to ask_coach" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_sports", "language" => "en", "selected_sports" => ["tennis"])
      Telegram::Handlers::SurveyHandler.handle_callback(cb("sport:skip_all"))
      state = Conversation.get(CHAT)
      assert_equal [],          state["selected_sports"]
      assert_equal "ask_coach", state["step"]
    end
  end

  test "sport:done sets skill_queue and moves to ask_skill" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_sports", "language" => "en", "selected_sports" => ["tennis", "padel"])
      Telegram::Handlers::SurveyHandler.handle_callback(cb("sport:done"))
      state = Conversation.get(CHAT)
      assert_equal "ask_skill", state["step"]
      assert_equal ["tennis", "padel"], state["skill_queue"]
    end
  end

  # ---- skill:set -----------------------------------------------------------

  test "skill:set records skill and moves to ask_coach when queue is empty" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_skill", "language" => "en",
                         "selected_sports" => ["tennis"], "skill_queue" => ["tennis"])
      Telegram::Handlers::SurveyHandler.handle_callback(cb("skill:set:tennis:beginner"))
      state = Conversation.get(CHAT)
      assert_equal "beginner",  state.dig("skills", "tennis")
      assert_equal [],          state["skill_queue"]
      assert_equal "ask_coach", state["step"]
    end
  end

  # ---- skill:skip ----------------------------------------------------------

  test "skill:skip advances queue without storing skill; moves to ask_coach when done" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_skill", "language" => "en",
                         "selected_sports" => ["tennis"], "skill_queue" => ["tennis"])
      Telegram::Handlers::SurveyHandler.handle_callback(cb("skill:skip:tennis"))
      state = Conversation.get(CHAT)
      assert_nil                state.dig("skills", "tennis")
      assert_equal "ask_coach", state["step"]
    end
  end

  # ---- coach ---------------------------------------------------------------

  test "coach:set:yes stores true and moves to ask_notifications" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_coach", "language" => "en")
      Telegram::Handlers::SurveyHandler.handle_callback(cb("coach:set:yes"))
      state = Conversation.get(CHAT)
      assert_equal true,                state["coach"]
      assert_equal "ask_notifications", state["step"]
    end
  end

  test "coach:set:no stores false" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_coach", "language" => "en")
      Telegram::Handlers::SurveyHandler.handle_callback(cb("coach:set:no"))
      state = Conversation.get(CHAT)
      assert_equal false, state["coach"]
      assert_equal "ask_notifications", state["step"]
    end
  end

  test "coach:skip stores nil and moves to ask_notifications" do
    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_coach", "language" => "en")
      Telegram::Handlers::SurveyHandler.handle_callback(cb("coach:skip"))
      state = Conversation.get(CHAT)
      assert_nil                        state["coach"]
      assert_equal "ask_notifications", state["step"]
    end
  end

  # ---- notifications + finish_survey ---------------------------------------

  test "notifications:set:yes finishes survey and calls MenuHandler.menu" do
    user = User.create!(email: "survey_finish_#{SecureRandom.hex(4)}@example.com", name: "Fin")
    menu_called = false

    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_notifications", "language" => "en")
      stub_singleton(User, :find_by, ->(**_kw) { user }) do
        stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(_) { menu_called = true }) do
          stub_singleton(Telegram::Helpers::UserProfile, :persist_from_conversation, ->(*, **) { true }) do
            Telegram::Handlers::SurveyHandler.handle_callback(cb("notifications:set:yes"))
          end
        end
      end
    end

    assert menu_called
  ensure
    user&.destroy
  end

  test "finish_survey sets onboarded_at on the user" do
    user = User.create!(email: "onboard_#{SecureRandom.hex(4)}@example.com", name: "Onboard")
    assert_nil user.onboarded_at

    with_memory_cache do
      Conversation.start(CHAT, "step" => "ask_notifications", "language" => "en")
      stub_singleton(User, :find_by, ->(**_kw) { user }) do
        stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(_) {}) do
          Telegram::Handlers::SurveyHandler.handle_callback(cb("notifications:skip"))
        end
      end
    end

    user.reload
    assert_not_nil user.onboarded_at
  ensure
    user&.destroy
  end
end
