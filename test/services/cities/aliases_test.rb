require "test_helper"

class Cities::AliasesTest < ActiveSupport::TestCase
  # Цели алиасов из справочника production (выгрузка от 2026-10-08):
  # geoname_id => [name, country_code].
  REFERENCE_TARGETS = {
    1486209 => [ "Yekaterinburg", "RU" ],
    2761369 => [ "Vienna", "AT" ],
    792680 => [ "Belgrade", "RS" ],
    611717 => [ "Tbilisi", "GE" ],
    3165524 => [ "Turin", "IT" ],
    3169070 => [ "Rome", "IT" ],
    524901 => [ "Moscow", "RU" ],
    498817 => [ "Saint Petersburg", "RU" ],
    1512569 => [ "Tashkent", "UZ" ],
    1504826 => [ "Kamensk-Ural’skiy", "RU" ],
    1501321 => [ "Kurgan", "RU" ],
    1508291 => [ "Chelyabinsk", "RU" ],
    1526273 => [ "Astana", "KZ" ],
    616052 => [ "Yerevan", "AM" ]
  }.freeze

  test "every configured target exists in the directory with the stated country and name" do
    REFERENCE_TARGETS.each do |geoname_id, (name, country_code)|
      City.create!(name: name, asciiname: name, country_code: country_code, geoname_id: geoname_id)
    end

    aliases = Cities::Aliases.default
    assert_operator aliases.entries.size, :>, 0
    assert_empty aliases.problems
  end

  test "global is set only on spellings that are unambiguous worldwide" do
    global = Cities::Aliases.default.entries.select(&:global).map(&:name)

    assert_equal %w[Astana Chelyabinsk Ekaterinburg Erevan Kamensk-Uralskiy Kamensk-Uralsky Kurgan Yekaterinburg Yerevan], global.sort
  end

  test "problems reports missing, foreign and renamed targets" do
    City.create!(name: "Moskva", asciiname: "Moskva", country_code: "TJ", geoname_id: 524901)
    City.create!(name: "Wien", asciiname: "Wien", country_code: "AT", geoname_id: 2761369)

    problems = Cities::Aliases.default.problems.join("\n")

    assert_match(/Moskva \(RU\) → 524901 Moscow: цель в стране TJ/, problems)
    assert_match(/Wien \(AT\) → 2761369 Vienna: цель называется Wien/, problems)
    assert_match(/Torino \(IT\) → 3165524 Turin: цели нет в справочнике/, problems)
  end

  test "one spelling with several targets keeps every candidate" do
    aliases = Cities::Aliases.new([
      { "name" => "Dual", "country_code" => "XX", "geoname_id" => 1, "city" => "One", "global" => true },
      { "name" => "Dual", "country_code" => "XX", "geoname_id" => 2, "city" => "Two", "global" => true }
    ])

    assert_equal [ 1, 2 ], aliases.entries_for("dual", country_code: "XX").map(&:geoname_id)
    assert_equal [ 1, 2 ], aliases.global_entries_for("dual").map(&:geoname_id)
    # Для строкового сравнения такое написание свести не к чему.
    assert_empty aliases.name_aliases
  end

  test "invalid rows are rejected" do
    [
      { "name" => "X", "country_code" => "ru", "geoname_id" => 1, "city" => "Y" },
      { "name" => "X", "country_code" => "RU", "geoname_id" => "1", "city" => "Y" },
      { "name" => "", "country_code" => "RU", "geoname_id" => 1, "city" => "Y" },
      { "name" => "X", "country_code" => "RU", "geoname_id" => 1, "city" => "Y", "global" => "yes" }
    ].each do |row|
      assert_raises(ArgumentError) { Cities::Aliases.new([ row ]) }
    end
  end

  test "global aliases keep the old string comparison of Ekaterinburg and Yekaterinburg" do
    # Каменск сводится к написанию справочника: ’ после транслитерации — «?».
    expected = { "ekaterinburg" => "yekaterinburg", "erevan" => "yerevan",
                 "kamensk-uralsky" => "kamensk-ural?skiy", "kamensk-uralskiy" => "kamensk-ural?skiy" }
    assert_equal expected, Cities::Aliases.default.name_aliases
  end
end
