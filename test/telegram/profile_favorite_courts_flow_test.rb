require "test_helper"
require "support/cache_helper"

class Telegram::Flows::Profile::FavoriteCourtsFlowTest < ActiveSupport::TestCase
  include CacheHelper

  test "toggle updates selections in cache" do
    user = User.create!(email: "tg_favorite_toggle_#{SecureRandom.hex(4)}@example.com", telegram_chat_id: "tg_fc_1")
    court = Court.create!(name: "Center Court", moderation_status: "approved")

    with_memory_cache do
      Rails.cache.write("tg:conv:tg_fc_1", { "flow" => "profile_favorite_courts", "selections" => [], "page" => 1 }, expires_in: 2.hours)
      stub_singleton(Telegram::Helpers::UserLookup, :find_user, ->(_) { user }) do
        stub_singleton(Telegram::Helpers::UserLookup, :locale_for, ->(_) { "en" }) do
          stub_singleton(Telegram::Flows::Profile::FavoriteCourtsFlow, :render_menu, ->(*_) { true }) do
            Telegram::Flows::Profile::FavoriteCourtsFlow.process_favorite_courts_callback("tg_fc_1", "toggle", court.id.to_s)
          end
        end
      end

      assert_equal [ court.id ], Rails.cache.read("tg:conv:tg_fc_1")["selections"]
    end
  ensure
    user&.destroy
    court&.destroy
  end

  test "render_menu includes pagination callback when multiple pages exist" do
    user = User.create!(email: "tg_favorite_page_#{SecureRandom.hex(4)}@example.com", telegram_chat_id: "tg_fc_2", city_name: "Moscow")
    6.times { |idx| Court.create!(name: "Court #{idx}", city_name: "Moscow", moderation_status: "approved") }
    sent_buttons = nil

    stub_singleton(Telegram::Helpers::UserLookup, :find_user, ->(_) { user }) do
      stub_singleton(Telegram::Helpers::UserLookup, :locale_for, ->(_) { "en" }) do
        stub_singleton(Telegram::Api, :send_with_buttons, ->(_chat_id, _text, buttons) { sent_buttons = buttons }) do
          Telegram::Flows::Profile::FavoriteCourtsFlow.render_menu("tg_fc_2", [], 1, nil, nil)
        end
      end
    end

    flat_buttons = sent_buttons.flatten
    assert_includes flat_buttons.map { |button| button[:callback_data] }, "profile:favorite_courts:page:2"
  ensure
    Court.where("name LIKE ?", "Court %").destroy_all
    user&.destroy
  end

  test "save persists favorite courts and clears note" do
    user = User.create!(
      email: "tg_favorite_save_#{SecureRandom.hex(4)}@example.com",
      telegram_chat_id: "tg_fc_3",
      court_preferences_note: "All city courts"
    )
    court = Court.create!(name: "Center Court", moderation_status: "approved")

    with_memory_cache do
      Rails.cache.write("tg:conv:tg_fc_3", { "flow" => "profile_favorite_courts", "selections" => [ court.id ], "page" => 1 }, expires_in: 2.hours)
      stub_singleton(Telegram::Helpers::UserLookup, :find_user, ->(_) { user }) do
        stub_singleton(Telegram::Helpers::UserLookup, :locale_for, ->(_) { "en" }) do
          stub_singleton(Telegram::Flows::ProfileFlow, :start_edit_profile, ->(*_) { true }) do
            stub_singleton(Telegram::Api, :answer_callback, ->(*) { true }) do
              Telegram::Flows::Profile::FavoriteCourtsFlow.process_favorite_courts_callback("tg_fc_3", "save", nil, cb_id: "cb1", message_id: 1)
            end
          end
        end
      end
    end

    user.reload
    assert_equal [ court.id ], user.favorite_court_ids
    assert_nil user.court_preferences_note
  ensure
    user&.destroy
    court&.destroy
  end

  test "cancel clears conversation and returns to profile edit" do
    user = User.create!(email: "tg_favorite_cancel_#{SecureRandom.hex(4)}@example.com", telegram_chat_id: "tg_fc_4")
    returned = false

    with_memory_cache do
      Rails.cache.write("tg:conv:tg_fc_4", { "flow" => "profile_favorite_courts", "selections" => [], "page" => 1 }, expires_in: 2.hours)
      stub_singleton(Telegram::Helpers::UserLookup, :find_user, ->(_) { user }) do
        stub_singleton(Telegram::Helpers::UserLookup, :locale_for, ->(_) { "en" }) do
          stub_singleton(Telegram::Flows::ProfileFlow, :start_edit_profile, ->(*_) { returned = true }) do
            stub_singleton(Telegram::Api, :answer_callback, ->(*) { true }) do
              Telegram::Flows::Profile::FavoriteCourtsFlow.process_favorite_courts_callback("tg_fc_4", "cancel", nil, cb_id: "cb1", message_id: 1)
            end
          end
        end
      end

      assert_equal({}, Rails.cache.read("tg:conv:tg_fc_4") || {})
    end

    assert returned
  ensure
    user&.destroy
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
