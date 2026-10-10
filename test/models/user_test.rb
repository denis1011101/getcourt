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

  test "recent_teammates lists people from my games, freshest first, without me and the excluded" do
    me = User.create!(email: "recent-me-#{SecureRandom.hex(4)}@example.com")
    old_friend, new_friend, booked, stranger = %w[old new booked stranger].map do |tag|
      User.create!(email: "recent-#{tag}-#{SecureRandom.hex(4)}@example.com", name: "Recent #{tag}")
    end
    mine = Game.create!(user: me, court: courts(:one), date: Date.new(2026, 9, 7), recurring: true)
    theirs = Game.create!(user: stranger, court: courts(:one), date: Date.new(2026, 9, 7))

    travel_to(2.days.ago) { mine.participations.create!(user: old_friend) }
    mine.participations.create!(user: me)
    mine.prebookings.create!(user: new_friend, date: Date.new(2026, 9, 14), slot_index: 1)
    mine.participations.create!(user: booked)
    theirs.participations.create!(user: stranger)

    assert_equal [ booked, new_friend, old_friend ], me.recent_teammates
    assert_equal [ new_friend, old_friend ], me.recent_teammates(except: [ booked.id ])
    assert_equal [ booked ], me.recent_teammates(limit: 1)
  end

  test "recent_coaches keeps only selectable coaches of my latest games" do
    me = User.create!(email: "recent-coach-me-#{SecureRandom.hex(4)}@example.com")
    anna, boris, gone = %w[anna boris gone].map do |tag|
      User.create!(email: "recent-coach-#{tag}-#{SecureRandom.hex(4)}@example.com", name: tag.capitalize, coach: true)
    end
    older = Game.create!(user: me, court: courts(:one), date: Date.new(2026, 9, 7))
    newer = Game.create!(user: me, court: courts(:one), date: Date.new(2026, 9, 8))
    without_coach = Game.create!(user: me, court: courts(:one), date: Date.new(2026, 9, 9))
    older.update_columns(with_coach: true, coach_id: anna.id, updated_at: 2.days.ago)
    newer.update_columns(with_coach: true, coach_id: boris.id, updated_at: 1.day.ago)
    # Галочку «с тренером» сняли — оставшийся coach_id тренером игры не считается.
    without_coach.update_columns(coach_id: gone.id)

    assert_equal [ boris, anna ], me.recent_coaches(among: [ anna, boris, gone ])
    assert_equal [ anna ], me.recent_coaches(among: [ anna, gone ])
  end
end
