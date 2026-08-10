require "test_helper"

class Telegram::Handlers::StartHandlerTest < ActiveSupport::TestCase
  def make_message(chat_id)
    { "chat" => { "id" => chat_id } }
  end

  test "new user receives site link without survey" do
    user = User.new
    menu_chat_id = nil
    survey_called = false

    stub_singleton(Telegram::UserService, :find_or_create_for_chat, ->(_, language_code:) { [ user, true ] }) do
      stub_singleton(Telegram::Handlers::SurveyHandler, :start, ->(*) { survey_called = true }) do
        stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(cid) { menu_chat_id = cid }) do
          Telegram::Handlers::StartHandler.handle(make_message("111"))
        end
      end
    end

    assert_equal "111", menu_chat_id
    assert_not survey_called
  end

  test "existing user receives site link without survey" do
    user = User.new
    menu_chat_id = nil
    survey_called = false

    stub_singleton(Telegram::UserService, :find_or_create_for_chat, ->(_, language_code:) { [ user, false ] }) do
      stub_singleton(Telegram::Handlers::SurveyHandler, :start, ->(*) { survey_called = true }) do
        stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(cid) { menu_chat_id = cid }) do
          Telegram::Handlers::StartHandler.handle(make_message("222"))
        end
      end
    end

    assert_equal "222", menu_chat_id
    assert_not survey_called
  end

  test "exception in UserService falls through to menu" do
    menu_called = false
    survey_called = false

    stub_singleton(Telegram::UserService, :find_or_create_for_chat, ->(_, language_code:) { raise "db error" }) do
      stub_singleton(Telegram::Handlers::SurveyHandler, :start, ->(*) { survey_called = true }) do
        stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(_) { menu_called = true }) do
          assert_nothing_raised { Telegram::Handlers::StartHandler.handle(make_message("333")) }
        end
      end
    end

    assert menu_called
    assert_not survey_called
  end

  test "menu contains only the GetCourt site link" do
    sent = nil

    stub_singleton(Telegram::Helpers::UserLookup, :locale_for, ->(_) { "en" }) do
      stub_singleton(Telegram::Handlers::MenuHandler, :send_or_edit_with_buttons, ->(*args, **kwargs) { sent = [ args, kwargs ] }) do
        Telegram::Handlers::MenuHandler.menu("444")
      end
    end

    args, kwargs = sent
    assert_equal "444", args.first
    assert_equal "All actions are available on getcourt.co.", args.second
    assert_equal [ [ { text: "Open in browser", url: ENV.fetch("APP_HOST", "https://getcourt.co") } ] ], args.third
    assert_nil kwargs[:message_id]
  end

  test "missing chat_id returns early without calling any handler" do
    called = false
    stub_singleton(Telegram::UserService, :find_or_create_for_chat, ->(_, language_code:) { called = true; [ nil, false ] }) do
      Telegram::Handlers::StartHandler.handle({})
    end
    assert_not called
  end
end
