require "test_helper"

class TrainingBlockDiagramEditorTest < ActiveSupport::TestCase
  test "an empty block opens with one blank frame" do
    state = TrainingBlock::Diagram::Editor.new(nil).state

    assert_equal [ { "title" => "", "items" => [], "arrows" => [] } ], state["frames"]
    assert_equal 0, state["frame_index"]
    assert_equal "select", state["tool"]
  end

  test "labels fill the first free slot, so a deletion does not repeat a letter" do
    editor = TrainingBlock::Diagram::Editor.new(nil)
    editor.apply("select_tool", { "tool" => "player" })
    editor.apply("pointer_down", { "x" => 10, "y" => 10, "index" => nil })
    editor.apply("pointer_down", { "x" => 20, "y" => 20, "index" => nil })

    assert_equal %w[A B], labels(editor)

    editor.apply("select_tool", { "tool" => "select" })
    editor.apply("pointer_down", { "x" => 10, "y" => 10, "index" => 0 })
    editor.apply("pointer_up")
    editor.apply("delete_selected")
    editor.apply("select_tool", { "tool" => "player" })
    editor.apply("pointer_down", { "x" => 30, "y" => 30, "index" => nil })

    assert_equal %w[B A], labels(editor)
  end

  test "opponents are numbered up to the item limit" do
    editor = TrainingBlock::Diagram::Editor.new(nil)
    editor.apply("select_tool", { "tool" => "opponent" })
    TrainingBlock::Diagram::MAX_ITEMS.times { editor.apply("pointer_down", { "x" => 5, "y" => 5, "index" => nil }) }

    assert_equal (1..TrainingBlock::Diagram::MAX_ITEMS).map(&:to_s), labels(editor)

    editor.apply("pointer_down", { "x" => 5, "y" => 5, "index" => nil })

    assert_equal TrainingBlock::Diagram::MAX_ITEMS, items(editor).size
  end

  test "dragging a figure clamps it to the court instead of letting it off the grid" do
    editor = TrainingBlock::Diagram::Editor.new(nil)
    editor.apply("select_tool", { "tool" => "cone" })
    editor.apply("pointer_down", { "x" => 50, "y" => 50, "index" => nil })
    editor.apply("select_tool", { "tool" => "select" })
    editor.apply("pointer_down", { "x" => 50, "y" => 50, "index" => 0 })
    editor.apply("pointer_move", { "x" => -40, "y" => 900 })
    editor.apply("pointer_up")

    item = items(editor).sole
    assert_equal 0.0, item["x"]
    assert_equal TrainingBlock::Diagram::HEIGHT, item["y"]
  end

  test "a poke instead of a gesture leaves neither an arrow nor an undo step" do
    editor = TrainingBlock::Diagram::Editor.new(nil)
    editor.apply("select_tool", { "tool" => "cone" })
    editor.apply("pointer_down", { "x" => 10, "y" => 10, "index" => nil })

    editor.apply("select_tool", { "tool" => "run" })
    editor.apply("pointer_down", { "x" => 40, "y" => 40, "index" => nil })
    editor.apply("pointer_move", { "x" => 41, "y" => 40 })
    editor.apply("pointer_up")

    assert_empty editor.state["frames"].sole["arrows"]

    editor.apply("undo")

    assert_empty items(editor), "отмена должна снять конус, а не несуществующую стрелку"
  end

  test "a real drag stores the arrow" do
    editor = TrainingBlock::Diagram::Editor.new(nil)
    editor.apply("select_tool", { "tool" => "ball_path" })
    editor.apply("pointer_down", { "x" => 10, "y" => 10, "index" => nil })
    editor.apply("pointer_move", { "x" => 80, "y" => 150 })

    assert editor.state["capturing"], "пока тянут, браузер должен слать pointer_move"

    editor.apply("pointer_up")

    arrow = editor.state["frames"].sole["arrows"].sole
    assert_equal({ "kind" => "ball", "x1" => 10.0, "y1" => 10.0, "x2" => 80.0, "y2" => 150.0 }, arrow)
    assert_not editor.state["capturing"]
  end

  test "frames are added, duplicated and deleted within the limit" do
    editor = TrainingBlock::Diagram::Editor.new(nil)
    editor.apply("select_tool", { "tool" => "player" })
    editor.apply("pointer_down", { "x" => 10, "y" => 10, "index" => nil })
    editor.apply("duplicate_frame")

    assert_equal 2, editor.state["frames"].size
    assert_equal 1, editor.state["frame_index"]
    assert_equal %w[A], labels(editor)

    TrainingBlock::Diagram::MAX_FRAMES.times { editor.apply("add_frame") }

    assert_equal TrainingBlock::Diagram::MAX_FRAMES, editor.state["frames"].size

    TrainingBlock::Diagram::MAX_FRAMES.times { editor.apply("delete_frame") }

    assert_equal 1, editor.state["frames"].size, "последний кадр удалять некуда"
  end

  test "the hidden field already holds what the server will store" do
    editor = TrainingBlock::Diagram::Editor.new(nil)
    editor.apply("frame_title", { "title" => "Фаза 1" * 20 })
    editor.apply("select_tool", { "tool" => "player" })
    editor.apply("pointer_down", { "x" => 10, "y" => 10, "index" => nil })

    value = JSON.parse(editor.state["value"])

    assert_equal value, TrainingBlock::Diagram.normalize(editor.state["value"]),
      "поле формы должно быть уже нормализованным: сервер прогонит тот же код"
    assert_equal TrainingBlock::Diagram::MAX_TITLE, value["frames"].sole["title"].length
  end

  test "an empty diagram is submitted as empty, not as a blank frame" do
    editor = TrainingBlock::Diagram::Editor.new(nil)

    assert_equal({ "frames" => [] }, JSON.parse(editor.state["value"]))
  end

  test "an unknown operation changes nothing" do
    editor = TrainingBlock::Diagram::Editor.new(nil)
    before = editor.state

    editor.apply("drop_table", { "x" => 1 })
    editor.apply("select_tool", { "tool" => "rm -rf" })

    assert_equal before, editor.state
  end

  # Главная проверка эксперимента: тот же файл, что грузит Rails, должен
  # завестись там, где нет ни Rails, ни ActiveSupport, ни rubygems.
  test "the browser source runs in a bare ruby, without Rails" do
    script = <<~RUBY
      #{TrainingBlock::Diagram::Source.call}
      editor = TrainingBlock::Diagram::Editor.new(nil)
      editor.apply("select_tool", { "tool" => "player" })
      editor.apply("pointer_down", { "x" => 10, "y" => 900, "index" => nil })
      print editor.state["value"]
    RUBY

    # Гасим RUBYOPT и BUNDLE_GEMFILE: иначе подпроцесс подхватит bundler/setup
    # родителя и проверка «без Rails» перестанет что-либо проверять.
    bare = { "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
    output = IO.popen([ bare, RbConfig.ruby, "--disable=gems", "-e", script ], &:read)

    assert_predicate $?, :success?, output
    assert_equal(
      { "frames" => [ { "title" => "", "items" => [ { "kind" => "player", "label" => "A", "x" => 10.0, "y" => 200.0 } ], "arrows" => [] } ] },
      JSON.parse(output)
    )
  end

  private

  def items(editor)
    editor.state["frames"][editor.state["frame_index"]]["items"]
  end

  def labels(editor)
    items(editor).map { |item| item["label"] }
  end
end
