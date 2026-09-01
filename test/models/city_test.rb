require "test_helper"

class CityTest < ActiveSupport::TestCase
  test "normalize_name folds case, spacing and diacritics" do
    assert_equal "bastad", City.normalize_name("  Båstad ")
    assert_equal "acapulco de juarez", City.normalize_name("Acapulco  de   Juárez")
  end

  test "normalize_name maps known transliteration variants together" do
    assert_equal City.normalize_name("Ekaterinburg"), City.normalize_name("Yekaterinburg")
  end

  test "normalize_name keeps cities that merely start with Y" do
    # Прежний вариант в tournaments_flow срезал ведущую Y перед гласной и
    # превращал York в «ork», а Yokohama — в «okohama».
    assert_equal "york", City.normalize_name("York")
    assert_equal "yokohama", City.normalize_name("Yokohama")
  end

  test "normalize_name returns nil for blank input" do
    assert_nil City.normalize_name(nil)
    assert_nil City.normalize_name("   ")
  end

  test "alias_names_for lists every spelling that folds into the name" do
    assert_equal %w[ekaterinburg yekaterinburg], City.alias_names_for("ekaterinburg").sort
    assert_equal [ "moscow" ], City.alias_names_for("moscow")
  end
end
