require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "labels a player with the handle they are known by" do
    named = User.create!(email: "labelled@example.com", name: "Denis", telegram_username: "denis_nick")

    assert_equal "Denis (@denis_nick)", user_display_label(named)
  end

  test "falls back to email when there is no telegram handle" do
    emailed = User.create!(email: "no-telegram@example.com", name: "Denis")

    assert_equal "Denis (no-telegram@example.com)", user_display_label(emailed)
  end

  test "shows the handle alone for players who never filled a name" do
    from_bot = User.create!(email: "bot-user@example.com", telegram_username: "only_nick")

    assert_equal "@only_nick", user_display_label(from_bot)
  end
end
