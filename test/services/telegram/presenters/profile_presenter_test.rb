require "test_helper"

class Telegram::Presenters::ProfilePresenterTest < ActiveSupport::TestCase
  def presenter(attrs = {})
    user = Struct.new(*attrs.keys, keyword_init: true).new(**attrs)
    Telegram::Presenters::ProfilePresenter.new(user)
  end

  # --- coach_label ---

  test "coach_label returns 'Yes' when coach is true" do
    assert_equal "Yes", presenter(coach: true).coach_label
  end

  test "coach_label returns 'No' when coach is false" do
    assert_equal "No", presenter(coach: false).coach_label
  end

  test "coach_label returns '—' when coach is nil" do
    assert_equal "—", presenter(coach: nil).coach_label
  end

  test "coach_label returns '—' when user has no coach attribute" do
    user = Object.new
    p = Telegram::Presenters::ProfilePresenter.new(user)
    assert_equal "—", p.coach_label
  end

  # --- about_me_label ---

  test "about_me_label returns text when present" do
    assert_equal "Tennis enthusiast", presenter(about_me: "Tennis enthusiast").about_me_label
  end

  test "about_me_label returns '—' when blank" do
    assert_equal "—", presenter(about_me: "").about_me_label
    assert_equal "—", presenter(about_me: nil).about_me_label
  end

  test "about_me_label returns '—' when user has no about_me attribute" do
    user = Object.new
    p = Telegram::Presenters::ProfilePresenter.new(user)
    assert_equal "—", p.about_me_label
  end

  test "favorite_courts_label returns joined court names" do
    user = User.create!(email: "presenter_favorites_#{SecureRandom.hex(4)}@example.com", name: "Coach")
    court_a = Court.create!(name: "Court A")
    court_b = Court.create!(name: "Court B")
    user.favorite_courts << [ court_a, court_b ]

    assert_equal "Court A, Court B", Telegram::Presenters::ProfilePresenter.new(user).favorite_courts_label
  ensure
    user&.destroy
    court_a&.destroy
    court_b&.destroy
  end

  test "court_note_label returns note when present" do
    assert_equal "All city courts", presenter(court_preferences_note: "All city courts").court_note_label
  end
end
