require "test_helper"

class TennisLifeMenuHandlerTest < ActiveSupport::TestCase
  def setup
    @chat_id = 123
    @fixed_time = Time.zone.parse("2026-03-07 15:11:10")
  end

  test "sends tennis life menu with refresh button and updated timestamp" do
    sent = nil

    with_stubbed_singleton_method(Telegram::Helpers::UserLookup, :locale_for, :ru) do
      with_stubbed_singleton_method(TennisScoreboard::Fetcher, :telegram_text, "Live scoreboard") do
        with_stubbed_singleton_method(Time, :current, @fixed_time) do
          with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(*args) { sent = args }) do
            Telegram::Handlers::TennisLifeMenuHandler.show(@chat_id)
          end
        end
      end
    end

    assert sent.present?
    assert_equal @chat_id, sent[0]
    assert_includes sent[1], "Обновлено: 15:11:10"
    assert_includes sent[1], "Live scoreboard"
    assert_equal [ { text: "Обновить", callback_data: "menu:tennis_life" } ], sent[2][0]
    assert_equal [ { text: "Главное меню", callback_data: "menu:main" } ], sent[2][1]
    assert_nil sent[3][:parse_mode]
  end

  test "edits existing tennis life menu when message id is provided" do
    edited = nil

    with_stubbed_singleton_method(Telegram::Helpers::UserLookup, :locale_for, :en) do
      with_stubbed_singleton_method(TennisScoreboard::Fetcher, :telegram_text, nil) do
        with_stubbed_singleton_method(Time, :current, @fixed_time) do
          with_stubbed_singleton_method(Telegram::Api, :edit_message_with_buttons, ->(*args) { edited = args }) do
            Telegram::Handlers::TennisLifeMenuHandler.show(@chat_id, message_id: 555)
          end
        end
      end
    end

    assert edited.present?
    assert_equal @chat_id, edited[0]
    assert_equal 555, edited[1]
    assert_includes edited[2], "Updated: 15:11:10"
    assert_equal [ { text: "Refresh", callback_data: "menu:tennis_life" } ], edited[3][0]
    assert_equal [ { text: "Main menu", callback_data: "menu:main" } ], edited[3][1]
    assert_nil edited[4][:parse_mode]
  end

  private

  def with_stubbed_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    had_method = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
    original = singleton.instance_method(method_name) if had_method
    callable = replacement.respond_to?(:call) ? replacement : ->(*) { replacement }

    singleton.define_method(method_name) do |*args, **kwargs, &block|
      callable.call(*args, **kwargs, &block)
    end

    yield
  ensure
    if had_method
      singleton.define_method(method_name, original)
    else
      singleton.remove_method(method_name)
    end
  end
end
