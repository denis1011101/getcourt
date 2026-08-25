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

  test "build_for updates the existing block instead of failing on its title" do
    coach = User.create!(email: "block-upsert@example.com", coach: true)
    existing = coach.training_blocks.create!(title: "Подача", duration_minutes: 20)

    block = TrainingBlock.build_for(coach, title: "подача", description: "Из-за головы", duration_minutes: 30)
    block.save!

    assert_equal existing, block
    assert_equal 1, coach.training_blocks.count
    assert_equal 30, block.duration_minutes
    assert_equal "Из-за головы", block.description
  ensure
    coach&.destroy
  end

  test "build_for returns an invalid block instead of swallowing it" do
    coach = User.create!(email: "block-blank@example.com", coach: true)

    block = TrainingBlock.build_for(coach, title: "   ", duration_minutes: "5")

    assert_not block.valid?
    assert_includes block.errors.attribute_names, :title
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

  test "available_for shows the shared blocks of other coaches" do
    coach = User.create!(email: "block-shared-owner@example.com", coach: true)
    stranger = User.create!(email: "block-shared-stranger@example.com", coach: true)
    shared = coach.training_blocks.create!(title: "Общая разминка", shared: true)
    personal = coach.training_blocks.create!(title: "Личный блок")

    visible = TrainingBlock.available_for([ stranger.id ])

    assert_includes visible, shared
    assert_not_includes visible, personal
  ensure
    coach&.destroy
    stranger&.destroy
  end

  test "available_for keeps a block that is already in the plan" do
    coach = User.create!(email: "block-shared-planned@example.com", coach: true)
    stranger = User.create!(email: "block-shared-planner@example.com", coach: true)
    personal = coach.training_blocks.create!(title: "Личный блок")

    assert_includes TrainingBlock.available_for([ stranger.id ], [ personal.id ]), personal
  ensure
    coach&.destroy
    stranger&.destroy
  end

  test "build_for shares a block and never unshares it from the game form" do
    coach = User.create!(email: "block-shared-toggle@example.com", coach: true)
    block = TrainingBlock.build_for(coach, title: "Подача", shared: "1")
    block.save!

    assert_predicate block, :shared?
    assert_predicate TrainingBlock.build_for(coach, title: "подача", description: "Из-за головы"), :shared?
  ensure
    coach&.destroy
  end
end
