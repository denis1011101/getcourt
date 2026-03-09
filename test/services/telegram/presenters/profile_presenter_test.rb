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
end
