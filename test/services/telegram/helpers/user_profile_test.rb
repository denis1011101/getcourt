require "test_helper"
require "support/cache_helper"

class Telegram::Helpers::UserProfileTest < ActiveSupport::TestCase
  include Telegram::Helpers
  include CacheHelper

  def build_user
    User.create!(email: "profile_#{SecureRandom.hex(4)}@example.com", name: "Test User")
  end

  def apply(user, state)
    Telegram::Helpers::UserProfile.apply_to_user(user, state)
  end

  test "maps language to telegram_locale" do
    u = build_user
    apply(u, "language" => "en")
    assert_equal "en", u.telegram_locale
  ensure; u.destroy; end

  test "maps city to city_name" do
    u = build_user
    apply(u, "city" => "moscow")
    assert_equal "moscow", u.city_name
  ensure; u.destroy; end

  test "maps selected_sports to preferred_sports as an Array" do
    u = build_user
    apply(u, "selected_sports" => ["Tennis", "Padel"])
    assert_instance_of Array, u.preferred_sports
    assert_includes u.preferred_sports, "Tennis"
  ensure; u.destroy; end

  test "preferred_sports is NOT a JSON string (regression)" do
    u = build_user
    apply(u, "selected_sports" => ["Tennis"])
    refute_kind_of String, u.preferred_sports
  ensure; u.destroy; end

  test "maps skills to skill_levels hash" do
    u = build_user
    apply(u, "skills" => { "Tennis" => "beginner" })
    assert_equal({ "Tennis" => "beginner" }, u.skill_levels)
  ensure; u.destroy; end

  test "maps coach true" do
    u = build_user; apply(u, "coach" => true); assert_equal true, u.coach
  ensure; u.destroy; end

  test "maps coach false" do
    u = build_user; apply(u, "coach" => false); assert_equal false, u.coach
  ensure; u.destroy; end

  test "maps coach nil (skipped)" do
    u = build_user; apply(u, "coach" => nil); assert_nil u.coach
  ensure; u.destroy; end

  test "maps notifications true to notify_nearby" do
    u = build_user; apply(u, "notifications" => true); assert_equal true, u.notify_nearby
  ensure; u.destroy; end

  test "maps notifications false to notify_nearby" do
    u = build_user; apply(u, "notifications" => false); assert_equal false, u.notify_nearby
  ensure; u.destroy; end

  test "nil notifications does not overwrite existing notify_nearby" do
    u = build_user
    u.notify_nearby = true
    apply(u, "notifications" => nil)
    assert_equal true, u.notify_nearby
  ensure; u.destroy; end

  test "persist_from_conversation finish:true clears cache and saves user" do
    u = build_user
    chat_id = "persist_#{SecureRandom.hex(4)}"
    with_memory_cache do
      Conversation.start(chat_id, "language" => "en", "city" => "Kazan")
      result = Telegram::Helpers::UserProfile.persist_from_conversation(chat_id, u, finish: true)
      assert result
      assert_equal({}, Conversation.get(chat_id))
    end
    u.reload
    assert_equal "en", u.telegram_locale
  ensure; u.destroy; end

  test "persist_from_conversation returns false for nil user" do
    assert_equal false, Telegram::Helpers::UserProfile.persist_from_conversation("any", nil, finish: true)
  end
end
