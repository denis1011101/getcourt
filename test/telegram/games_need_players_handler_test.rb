require "test_helper"

class Telegram::Handlers::GamesNeedPlayersHandlerTest < ActiveSupport::TestCase
  test "list_page prioritizes games on favorite courts" do
    user = User.create!(email: "games_need_players_user_#{SecureRandom.hex(4)}@example.com", telegram_chat_id: "gnp_user")
    favorite_court = Court.create!(name: "Favorite Court")
    other_court = Court.create!(name: "Other Court")
    user.favorite_courts << favorite_court
    owner = User.create!(email: "games_need_players_owner_#{SecureRandom.hex(4)}@example.com")

    favorite_game = Game.create!(user: owner, court: favorite_court, date: Date.current + 1.day, urgent_player_search: true)
    other_game = Game.create!(user: owner, court: other_court, date: Date.current + 1.day, urgent_player_search: true)
    sent_buttons = nil

    stub_singleton(Telegram::Helpers::UserLookup, :locale_for, ->(_) { "en" }) do
      stub_singleton(Telegram::Helpers::UserLookup, :find_user, ->(_) { user }) do
        stub_singleton(Telegram::Handlers::GamesHandler, :game_label, ->(game, **_) { "Game #{game.id}" }) do
          stub_singleton(Telegram::Handlers::GamesNeedPlayersHandler, :send_or_edit_with_buttons, ->(_chat_id, _text, buttons, **_kw) { sent_buttons = buttons }) do
            Telegram::Handlers::GamesNeedPlayersHandler.list_page("gnp_user")
          end
        end
      end
    end

    game_buttons = sent_buttons.select { |row| row.first[:callback_data].start_with?("game:show:") }
    assert_equal "game:show:#{favorite_game.id}:1", game_buttons.first.first[:callback_data]
  ensure
    favorite_game&.destroy
    other_game&.destroy
    user&.destroy
    owner&.destroy
    favorite_court&.destroy
    other_court&.destroy
  end

  private

  def stub_singleton(target, method_name, replacement)
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
