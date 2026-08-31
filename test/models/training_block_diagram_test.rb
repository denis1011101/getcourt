require "test_helper"

class TrainingBlockDiagramTest < ActiveSupport::TestCase
  test "the diagram arrives as a JSON string from the form and is stored as a structure" do
    diagram = TrainingBlock::Diagram.normalize({
      frames: [
        {
          title: "Фаза 1",
          items: [ { kind: "player", label: "A", x: 30, y: 120 } ],
          arrows: [ { kind: "run", x1: 30, y1: 120, x2: 60, y2: 80 } ]
        }
      ]
    }.to_json)

    frame = diagram["frames"].sole
    assert_equal "Фаза 1", frame["title"]
    assert_equal({ "kind" => "player", "label" => "A", "x" => 30.0, "y" => 120.0 }, frame["items"].sole)
    assert_equal "run", frame["arrows"].sole["kind"]
  end

  test "coordinates outside the grid are clamped instead of stored as sent" do
    diagram = TrainingBlock::Diagram.normalize(
      "frames" => [ { "items" => [ { "kind" => "ball", "x" => -50, "y" => 900 } ] } ]
    )

    item = diagram["frames"].sole["items"].sole
    assert_equal 0.0, item["x"]
    assert_equal TrainingBlock::Diagram::HEIGHT, item["y"]
  end

  test "figures and arrows of unknown kinds are dropped" do
    diagram = TrainingBlock::Diagram.normalize(
      "frames" => [ {
        "items" => [ { "kind" => "<script>", "x" => 10, "y" => 10 }, { "kind" => "cone", "x" => 10, "y" => 10 } ],
        "arrows" => [ { "kind" => "laser", "x1" => 0, "y1" => 0, "x2" => 50, "y2" => 50 } ]
      } ]
    )

    frame = diagram["frames"].sole
    assert_equal [ "cone" ], frame["items"].map { |item| item["kind"] }
    assert_empty frame["arrows"]
  end

  test "an arrow that is only a tap is not stored" do
    diagram = TrainingBlock::Diagram.normalize(
      "frames" => [ { "arrows" => [ { "kind" => "run", "x1" => 40, "y1" => 40, "x2" => 40.5, "y2" => 40.5 } ] } ]
    )

    assert_empty diagram["frames"]
  end

  test "frames, figures and arrows are capped" do
    frame = {
      "items" => Array.new(30) { { "kind" => "player", "x" => 10, "y" => 10 } },
      "arrows" => Array.new(30) { { "kind" => "run", "x1" => 0, "y1" => 0, "x2" => 50, "y2" => 50 } }
    }

    diagram = TrainingBlock::Diagram.normalize("frames" => Array.new(20) { frame })

    assert_equal TrainingBlock::Diagram::MAX_FRAMES, diagram["frames"].size
    assert_equal TrainingBlock::Diagram::MAX_ITEMS, diagram["frames"].first["items"].size
    assert_equal TrainingBlock::Diagram::MAX_ARROWS, diagram["frames"].first["arrows"].size
  end

  test "garbage instead of a diagram leaves the block without one" do
    [ nil, "", "not json", "[1,2,3]", 42, { "frames" => "нет" } ].each do |value|
      assert_equal({ "frames" => [] }, TrainingBlock::Diagram.normalize(value), "не пережили #{value.inspect}")
    end
  end

  test "the block reports whether it has a diagram at all" do
    coach = User.create!(email: "diagram-owner@example.com", coach: true)

    block = coach.training_blocks.create!(title: "Подача с выходом")
    assert_not block.diagram?
    assert_empty block.diagram_frames

    block.update!(diagram: { frames: [ { items: [ { kind: "player", label: "A", x: 50, y: 150 } ] } ] }.to_json)

    assert block.reload.diagram?
    assert_equal 1, block.diagram_frames.sole["items"].size
  ensure
    coach&.destroy
  end
end
