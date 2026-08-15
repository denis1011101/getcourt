require "test_helper"

class UserOnboardingPresenterTest < ActiveSupport::TestCase
  test "a fresh account has everything left to do" do
    user = User.create!(email: "fresh-onboarding@example.com")
    presenter = UserOnboardingPresenter.new(user: user)

    assert presenter.visible?
    assert_equal 0, presenter.completed_count
    assert_equal 4, presenter.total_count
    assert_equal 0, presenter.progress_percent
  end

  test "counts what is already filled in" do
    user = User.create!(email: "half-onboarding@example.com", city_name: "Yekaterinburg", telegram_chat_id: 55_001)
    presenter = UserOnboardingPresenter.new(user: user)

    assert presenter.visible?
    assert_equal 2, presenter.completed_count
    assert_equal 50, presenter.progress_percent
  end

  test "disappears once everything is done" do
    user = User.create!(
      email: "done-onboarding@example.com",
      city_name: "Yekaterinburg",
      telegram_chat_id: 55_002,
      preferred_sports: [ "tennis" ]
    )
    Game.create!(court: courts(:one), user: user, date: Date.current + 2.days)

    assert_not UserOnboardingPresenter.new(user: user).visible?
  end

  test "stays hidden after the user closes it" do
    user = User.create!(email: "dismissed-onboarding@example.com")
    user.dismiss_onboarding!

    assert_not UserOnboardingPresenter.new(user: user.reload).visible?
  end
end
