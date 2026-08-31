require "json"

class TrainingBlock
  # Схема корта у блока: несколько кадров («фаза 1», «фаза 2»), в каждом —
  # расставленные фигуры и нарисованные стрелки.
  #
  # Браузер присылает схему скрытым полем формы, то есть JSON-строкой, поэтому
  # разбор здесь защитный: что не влезает в формат — отбрасывается, а не
  # сохраняется как есть. Иначе произвольный POST кладёт в базу произвольную
  # структуру, которая потом уходит в SVG на странице.
  #
  # Этот же файл целиком уезжает в браузер и исполняется в ruby.wasm (см.
  # Diagram::Source и court_diagram/runtime.js), поэтому здесь только чистый
  # Ruby: ни Rails, ни ActiveSupport — там их нет. Отсюда `[0, N]` вместо
  # `first(N)` и `empty?` вместо `blank?`.
  class Diagram
    # Координатная сетка совпадает с viewBox в training_blocks/_court_markings:
    # 100 единиц в ширину, 200 в длину — это пропорции корта вместе с забегами.
    WIDTH = 100.0
    HEIGHT = 200.0

    MAX_FRAMES = 8
    MAX_ITEMS = 16
    MAX_ARROWS = 20
    MAX_TITLE = 40
    MAX_LABEL = 2

    ITEM_KINDS = %w[player opponent coach ball cone].freeze
    ARROW_KINDS = %w[run ball].freeze

    # Стрелка короче этого — промах пальцем, а не жест: такие не храним.
    MIN_ARROW_LENGTH = 3.0

    class << self
      def normalize(raw)
        frames = Array(hashify(raw)["frames"])
          .first(MAX_FRAMES)
          .map { |frame| normalize_frame(frame) }

        return { "frames" => [] } if frames.all? { |frame| blank_frame?(frame) }

        { "frames" => frames }
      end

      def frames(value)
        Array(hashify(value)["frames"])
      end

      def any?(value)
        frames(value).any? { |frame| !blank_frame?(frame) }
      end

      # Координата вне сетки — либо чужой POST, либо кривой пересчёт в браузере.
      # И то и другое лечится обрезкой: фигура останется на корте.
      def coordinate(value, max)
        number = Float(value, exception: false).to_f
        number = 0.0 unless number.finite?
        number.clamp(0.0, max).round(2)
      end

      private

      def normalize_frame(raw)
        frame = hashify(raw)

        {
          "title" => frame["title"].to_s.strip[0, MAX_TITLE],
          "items" => Array(frame["items"]).first(MAX_ITEMS).filter_map { |item| normalize_item(item) },
          "arrows" => Array(frame["arrows"]).first(MAX_ARROWS).filter_map { |arrow| normalize_arrow(arrow) }
        }
      end

      def normalize_item(raw)
        item = hashify(raw)
        kind = item["kind"].to_s
        return unless ITEM_KINDS.include?(kind)

        {
          "kind" => kind,
          "label" => item["label"].to_s.strip[0, MAX_LABEL],
          "x" => coordinate(item["x"], WIDTH),
          "y" => coordinate(item["y"], HEIGHT)
        }
      end

      def normalize_arrow(raw)
        arrow = hashify(raw)
        kind = arrow["kind"].to_s
        return unless ARROW_KINDS.include?(kind)

        points = {
          "x1" => coordinate(arrow["x1"], WIDTH), "y1" => coordinate(arrow["y1"], HEIGHT),
          "x2" => coordinate(arrow["x2"], WIDTH), "y2" => coordinate(arrow["y2"], HEIGHT)
        }
        length = Math.hypot(points["x2"] - points["x1"], points["y2"] - points["y1"])
        return if length < MIN_ARROW_LENGTH

        { "kind" => kind }.merge(points)
      end

      def blank_frame?(frame)
        frame["title"].empty? && frame["items"].empty? && frame["arrows"].empty?
      end

      def hashify(value)
        parsed =
          case value
          when Hash then value
          when String then parse_json(value)
          else {}
          end

        parsed.is_a?(Hash) ? parsed : {}
      end

      def parse_json(value)
        JSON.parse(value)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
