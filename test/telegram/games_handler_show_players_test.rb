require "test_helper"

class GamesHandlerShowPlayersTest < ActiveSupport::TestCase
  def setup
    @chat_id = 123
    @game = games(:one)
    @user = users(:one)
    @game.update!(user: @user)
  end

  test "renders players list with statistics and back button" do
    sent = nil

    with_stubbed_singleton_method(Telegram::Helpers::UserLookup, :locale_for, :en) do
      with_stubbed_singleton_method(Telegram::Api, :edit_message_with_buttons, ->(*args) { sent = args }) do
        Telegram::Handlers::GamesHandler.show_players(@chat_id, @game.id, 1, message_id: 555)
      end
    end

    assert sent.present?
    assert_equal @chat_id, sent[0]
    assert_equal 555, sent[1]
    assert_includes sent[2], "Players list (Game ##{@game.id})"
    assert sent[3].flatten.any? { |b| b.is_a?(Hash) && b[:text] == "Back to game" }
  end

  test "returns 'game not found' when missing" do
    sent = nil

    with_stubbed_singleton_method(Telegram::Helpers::UserLookup, :locale_for, :en) do
      with_stubbed_singleton_method(Telegram::Api, :send_simple, ->(*args) { sent = args }) do
        Telegram::Handlers::GamesHandler.show_players(@chat_id, -1, 1, message_id: nil)
      end
    end

    assert sent.present?
    assert_equal @chat_id, sent[0]
    assert_includes sent[1], "Game not found."
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
