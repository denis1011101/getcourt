require "test_helper"

class TelegramI18nMissingInterpolationTest < ActiveSupport::TestCase
  test "a missing interpolation argument is logged, not raised" do
    text = nil

    assert_nothing_raised do
      # players_list takes %{count}; the poller must survive a caller that forgets it.
      text = Telegram::I18n.t(:players, locale: "en", capacity: 4)
    end

    assert_includes text, "%{count}"
  end

  test "an unknown key returns the key itself" do
    assert_equal "definitely_not_a_key", Telegram::I18n.t(:definitely_not_a_key, locale: "en")
  end
end
