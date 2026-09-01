require "test_helper"

class Social::NamesTest < ActiveSupport::TestCase
  test "keeps the first name and initials the surname" do
    assert_equal "Denis L.", Social::Names.short("Denis Levenko")
    assert_equal "Denis L.", Social::Names.short("  Denis   levenko  ")
    assert_equal "Denis", Social::Names.short("Denis")
    assert_equal "", Social::Names.short(nil)
  end
end
