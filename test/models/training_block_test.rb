require "test_helper"

class TrainingBlockTest < ActiveSupport::TestCase
  test "a block belongs to one coach and needs a title" do
    coach = User.create!(email: "block-owner@example.com", coach: true)

    block = TrainingBlock.new(user: coach)

    assert_not block.valid?
    assert_includes block.errors.attribute_names, :title
  ensure
    coach&.destroy
  end

  test "the same title cannot be stored twice in one library" do
    coach = User.create!(email: "block-duplicate@example.com", coach: true)
    coach.training_blocks.create!(title: "Подача")

    duplicate = coach.training_blocks.new(title: "подача")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :title
  ensure
    coach&.destroy
  end

  test "upsert_for updates the existing block instead of failing on its title" do
    coach = User.create!(email: "block-upsert@example.com", coach: true)
    existing = coach.training_blocks.create!(title: "Подача", duration_minutes: 20)

    block = TrainingBlock.upsert_for(coach, title: "подача", description: "Из-за головы", duration_minutes: 30)

    assert_equal existing, block
    assert_equal 1, coach.training_blocks.count
    assert_equal 30, block.duration_minutes
    assert_equal "Из-за головы", block.description
  ensure
    coach&.destroy
  end

  test "upsert_for skips a blank title" do
    coach = User.create!(email: "block-blank@example.com", coach: true)

    assert_nil TrainingBlock.upsert_for(coach, title: "   ")
    assert_equal 0, coach.training_blocks.count
  ensure
    coach&.destroy
  end

  test "label shows the duration when it is set" do
    coach = User.create!(email: "block-label@example.com", coach: true)

    assert_equal "Подача", coach.training_blocks.create!(title: "Подача").label
    assert_equal "Приём · 15 #{I18n.t("training_blocks.minutes_short")}", coach.training_blocks.create!(title: "Приём", duration_minutes: 15).label
  ensure
    coach&.destroy
  end
end
