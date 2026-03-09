require "test_helper"

class Telegram::Handlers::StartHandlerTest < ActiveSupport::TestCase
  def make_message(chat_id)
    { "chat" => { "id" => chat_id } }
  end

  test "new user triggers SurveyHandler.start" do
    user = User.new
    survey_args = nil

    stub_singleton(Telegram::UserService, :find_or_create_for_chat, ->(_) { [ user, true ] }) do
      stub_singleton(Telegram::Handlers::SurveyHandler, :start, ->(cid, u) { survey_args = [ cid, u ] }) do
        Telegram::Handlers::StartHandler.handle(make_message("111"))
      end
    end

    assert_equal [ "111", user ], survey_args
  end

  test "existing user triggers MenuHandler.menu" do
    user = User.new
    menu_chat_id = nil
    survey_called = false

    stub_singleton(Telegram::UserService, :find_or_create_for_chat, ->(_) { [ user, false ] }) do
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

    stub_singleton(Telegram::UserService, :find_or_create_for_chat, ->(_) { raise "db error" }) do
      stub_singleton(Telegram::Handlers::SurveyHandler, :start, ->(*) { survey_called = true }) do
        stub_singleton(Telegram::Handlers::MenuHandler, :menu, ->(_) { menu_called = true }) do
          assert_nothing_raised { Telegram::Handlers::StartHandler.handle(make_message("333")) }
        end
      end
    end

    assert menu_called
    assert_not survey_called
  end

  test "missing chat_id returns early without calling any handler" do
    called = false
    stub_singleton(Telegram::UserService, :find_or_create_for_chat, ->(_) { called = true; [ nil, false ] }) do
      Telegram::Handlers::StartHandler.handle({})
    end
    assert_not called
  end
end
