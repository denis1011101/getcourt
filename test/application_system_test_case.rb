require "test_helper"
require "capybara/selenium/driver"
require "capybara/selenium/driver_specializations/chrome_driver"

module ChromeSessionReset
  def reset!
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError => error
    raise unless error.message.start_with?("invalid argument: * is not a valid URL")

    # Chrome 158 rejects Capybara's wildcard origin. Quit to discard the session's storage.
    quit
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeSessionReset)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :rack_test
end
