require "test_helper"

module Telegram
  module Flows
    class StatsFlowTest < ActiveSupport::TestCase
      test "approved participant can fill stats, non participant cannot" do
        game = games(:one)
        participant = users(:two)
        outsider = User.create!(name: "Outsider", email: "outsider@example.test")

        Participation.find_or_create_by!(game: game, user: participant) do |p|
          p.status = "approved"
        end

        assert Telegram::Flows::StatsFlow.send(:can_fill_stats_for_game?, participant, game)
        assert_not Telegram::Flows::StatsFlow.send(:can_fill_stats_for_game?, outsider, game)
      end

      test "render_menu uses earlier hours entry when latest entry has no hours key" do
        game = games(:one)
        game.update!(players_count: 4)

        creator = game.user
        actor = users(:two)
        another_user = User.create!(name: "Another user", email: "another-user@example.test")

        PlayerStatisticEntry.create!(
          user: creator,
          game: game,
          actor: actor,
          source: "telegram",
          recorded_at: 2.hours.ago,
          data: { "doubles_hours" => 1.5 }
        )

        PlayerStatisticEntry.create!(
          user: another_user,
          game: game,
          actor: actor,
          source: "telegram",
          recorded_at: 1.hour.ago,
          data: { "aces" => 3 }
        )

        sent_text = nil

        with_stubbed_singleton_method(Telegram::Helpers::Conversation, :get, ->(_chat_id) { {} }) do
          with_stubbed_singleton_method(Telegram::Helpers::UserLookup, :locale_for, ->(_chat_id) { :ru }) do
            with_stubbed_singleton_method(Telegram::Api, :send_with_buttons, ->(_chat_id, text, _buttons) { sent_text = text }) do
              Telegram::Flows::StatsFlow.send(:render_menu, 123, game_id: game.id, entered: {})
            end
          end
        end

        assert_includes sent_text, "Игровое время: 1.5 ч"
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
  end
end
