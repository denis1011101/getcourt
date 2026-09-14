require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires email even when telegram chat id is present" do
    user = User.new(telegram_chat_id: "12345", name: "Telegram User")

    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "accepts generated telegram account email" do
    user = User.new(
      email: "tg-#{SecureRandom.hex(8)}@telegram.getcourt",
      telegram_chat_id: "54321",
      telegram_generated_email: true,
      name: "Telegram User"
    )

    assert user.valid?
  end

  test "telegram locale is optional without an implicit default" do
    column = User.columns_hash.fetch("telegram_locale")

    assert column.null
    assert_nil column.default
    assert_nil User.new.telegram_locale
  end

  test "defaults notification channel to telegram when telegram is connected" do
    user = User.new(email: "telegram-channel@example.com", telegram_chat_id: 12_345)

    assert user.valid?
    assert_equal "telegram", user.notification_channel
  end

  test "defaults notification channel to email without telegram" do
    user = User.new(email: "email-channel@example.com")

    assert user.valid?
    assert_equal "email", user.notification_channel
  end

  test "identifiable keeps players who only have a telegram handle" do
    from_bot = User.create!(email: "pickable-bot@example.com", telegram_username: "pickable_nick")
    nameless = User.create!(email: "not-pickable@example.com")

    identifiable = User.identifiable

    assert_includes identifiable, from_bot
    assert_not_includes identifiable, nameless
  end

  test "by_display_label sorts by what the picker shows" do
    zoe = User.create!(email: "zoe-sorted@example.com", name: "Zoe")
    anna = User.create!(email: "anna-sorted@example.com", name: "anna")

    ordered = User.where(id: [ zoe.id, anna.id ]).by_display_label

    assert_equal [ anna, zoe ], ordered.to_a
  end

  test "the telegram handle is canonical no matter how the nick was typed" do
    user = User.new(telegram_username: "  @Nick_Name  ")

    assert_equal "@Nick_Name", user.telegram_handle
  end

  test "a nick too short to be a telegram username gives no handle" do
    assert_nil User.new(telegram_username: "abcd").telegram_handle
    assert_nil User.new(telegram_username: nil).telegram_handle
  end

  # Подпись уходит всей команде, поэтому e-mail в неё не попадает никогда:
  # почта одного игрока не должна становиться известной остальным.
  test "broadcast_label never falls back to the email" do
    user = User.create!(email: "broadcast-nameless@example.com")

    assert_nil user.broadcast_label
  end

  test "broadcast_label puts the handle next to the name" do
    named = User.new(name: "Marina", telegram_username: "marina_tg")
    handle_only = User.new(telegram_username: "marina_tg")
    name_only = User.new(name: "Marina")

    assert_equal "Marina (@marina_tg)", named.broadcast_label
    assert_equal "@marina_tg", handle_only.broadcast_label
    assert_equal "Marina", name_only.broadcast_label
  end

  # Подсказки в поле выбора игрока: первые буквы имени, ника или почты, без
  # оглядки на регистр — в том числе кириллицы, которую lower() SQLite не берёт.
  test "search_pickable matches the start of a name in any case, cyrillic included" do
    denis = User.create!(email: "picker-denis@example.com", name: "Денис Левенко")
    other = User.create!(email: "picker-other@example.com", name: "Марина")

    assert_equal [ denis ], User.search_pickable("ден")
    assert_equal [ denis ], User.search_pickable("ЛЕВ")
    assert_equal [ other ], User.search_pickable("мар")
  end

  test "search_pickable finds people by telegram nick with or without @ and by email" do
    user = User.create!(email: "picker-nick@example.com", telegram_username: "court_rat")

    assert_equal [ user ], User.search_pickable("@cou")
    assert_equal [ user ], User.search_pickable("court_r")
    assert_equal [ user ], User.search_pickable("picker-nick@")
  end

  test "search_pickable ranks matches at the start of a word above the rest" do
    inside = User.create!(email: "picker-inside@example.com", name: "Adrian")
    word_start = User.create!(email: "picker-word@example.com", name: "Peter Ian")
    start = User.create!(email: "picker-start@example.com", name: "Ian Smith")

    assert_equal [ start, word_start, inside ], User.search_pickable("ian")
  end

  test "search_pickable skips merged and nameless accounts and caps the list" do
    merged = User.create!(email: "picker-merged@example.com", name: "Zed Merged", merged_at: Time.current)
    User.create!(email: "picker-zed-nameless@example.com")
    kept = 3.times.map { |i| User.create!(email: "picker-zed-#{i}@example.com", name: "Zed #{i}") }

    assert_equal kept.first(2), User.search_pickable("zed", limit: 2)
    assert_not_includes User.search_pickable("zed"), merged
    assert_not_includes User.search_pickable("picker-zed-nameless"), User.find_by!(email: "picker-zed-nameless@example.com")
    assert_empty User.search_pickable("   ")
  end
end
