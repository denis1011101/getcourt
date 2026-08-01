require "test_helper"

class CourtSuggestionsLocalesTest < ActiveSupport::TestCase
  KEYS = %w[
    courts.suggestions.hint
    courts.suggestions.cta
    courts.suggestions.new_title
    courts.suggestions.new_help
    courts.suggestions.submit
    courts.suggestions.created
    courts.suggestions.index_title
    courts.suggestions.approve
    courts.suggestions.reject
  ].freeze

  test "court suggestion copy exists in every web locale" do
    User::WEB_LOCALES.each do |locale|
      KEYS.each do |key|
        assert I18n.exists?(key, locale), "Missing #{key} for #{locale}"
      end
    end
  end
end
