class TrainingBlock
  class Diagram
    # Состояние редактора схемы: какой кадр открыт, что выделено, что тащат
    # прямо сейчас, и стопка отмены.
    #
    # Живёт в ruby.wasm в браузере: Stimulus присылает жест («нажали в такой-то
    # точке», «отпустили»), получает обратно снимок состояния и рисует его. До
    # этого те же лимиты, подписи и клампы были продублированы в JS — редактор
    # честно повторял серверные правила ровно до первого расхождения.
    #
    # Как и Diagram, только чистый Ruby: ни Rails, ни ActiveSupport.
    class Editor
      # Инструмент «стрелка бега» и «стрелка мяча» кладут разный kind в одну и
      # ту же фигуру.
      ARROW_TOOLS = { "run" => "run", "ball_path" => "ball" }.freeze
      TOOLS = ([ "select" ] + Diagram::ITEM_KINDS + ARROW_TOOLS.keys).freeze

      UNDO_LIMIT = 20

      PLAYER_LABELS = ("A".."Z").to_a.freeze
      OPPONENT_LABELS = (1..Diagram::MAX_ITEMS).map(&:to_s).freeze

      def initialize(diagram = nil)
        @frames = Diagram.frames(diagram).map { |frame| frame_from(frame) }
        @frames << blank_frame if @frames.empty?

        @frame_index = 0
        @tool = "select"
        @selected = nil
        @dragging = nil
        @draft = nil
        @undo = []
      end

      # Единственная дверь снаружи: имена операций перечислены здесь же, поэтому
      # что бы браузер ни прислал, дальше case он не пройдёт.
      def apply(op, args = nil)
        args = {} unless args.is_a?(Hash)

        case op
        when "select_tool" then select_tool(args["tool"])
        when "pointer_down" then pointer_down(args["x"], args["y"], args["index"])
        when "pointer_move" then pointer_move(args["x"], args["y"])
        when "pointer_up" then pointer_up
        when "delete_selected" then delete_selected
        when "clear_frame" then clear_frame
        when "undo" then undo
        when "select_frame" then select_frame(args["index"])
        when "add_frame" then add_frame
        when "duplicate_frame" then duplicate_frame
        when "delete_frame" then delete_frame
        when "frame_title" then frame_title(args["title"])
        end

        self
      end

      # Снимок для браузера: из него рисуются кадр, вкладки и панель.
      #
      # "value" — это уже нормализованная схема, ровно то, что сохранит сервер:
      # скрытое поле формы заполняется тем же кодом, который потом проверит POST.
      def state
        {
          "frames" => @frames,
          "frame_index" => @frame_index,
          "tool" => @tool,
          "selected" => @selected,
          "draft" => @draft,
          "capturing" => !(@dragging.nil? && @draft.nil?),
          "value" => JSON.generate(Diagram.normalize({ "frames" => @frames }))
        }
      end

      private

      def frame
        @frames[@frame_index]
      end

      def select_tool(tool)
        return unless TOOLS.include?(tool)

        @tool = tool
        @selected = nil
      end

      def pointer_down(x, y, index)
        x = Diagram.coordinate(x, Diagram::WIDTH)
        y = Diagram.coordinate(y, Diagram::HEIGHT)

        if @tool == "select"
          @selected = item_index(index)
          return if @selected.nil?

          push_undo
          @dragging = @selected
          return
        end

        if Diagram::ITEM_KINDS.include?(@tool)
          return if frame["items"].size >= Diagram::MAX_ITEMS

          push_undo
          frame["items"] << { "kind" => @tool, "label" => next_label(@tool), "x" => x, "y" => y }
          return
        end

        kind = ARROW_TOOLS[@tool]
        return if kind.nil? || frame["arrows"].size >= Diagram::MAX_ARROWS

        push_undo
        @draft = { "kind" => kind, "x1" => x, "y1" => y, "x2" => x, "y2" => y }
      end

      def pointer_move(x, y)
        return if @dragging.nil? && @draft.nil?

        x = Diagram.coordinate(x, Diagram::WIDTH)
        y = Diagram.coordinate(y, Diagram::HEIGHT)

        if @draft
          @draft["x2"] = x
          @draft["y2"] = y
          return
        end

        item = frame["items"][@dragging]
        return @dragging = nil if item.nil?

        item["x"] = x
        item["y"] = y
      end

      def pointer_up
        if @draft
          length = Math.hypot(@draft["x2"] - @draft["x1"], @draft["y2"] - @draft["y1"])
          if length >= Diagram::MIN_ARROW_LENGTH
            frame["arrows"] << @draft
          else
            # Тычок вместо жеста: ни стрелки, ни шага в истории отмены.
            @undo.pop
          end
          @draft = nil
        end

        @dragging = nil
      end

      def delete_selected
        return if @selected.nil?

        push_undo
        frame["items"].delete_at(@selected)
        @selected = nil
      end

      def clear_frame
        push_undo
        @frames[@frame_index] = blank_frame(frame["title"])
        @selected = nil
      end

      def undo
        snapshot = @undo.pop
        return if snapshot.nil?

        @frames = JSON.parse(snapshot)
        @frame_index = [ @frame_index, @frames.size - 1 ].min
        @selected = nil
        @dragging = nil
        @draft = nil
      end

      def select_frame(index)
        index = index.to_i
        return unless (0...@frames.size).cover?(index)

        @frame_index = index
        @selected = nil
      end

      def add_frame
        return if @frames.size >= Diagram::MAX_FRAMES

        push_undo
        @frames << blank_frame
        @frame_index = @frames.size - 1
        @selected = nil
      end

      # Фазы упражнения отличаются одним-двумя шагами, поэтому следующий кадр
      # почти всегда начинается с копии предыдущего.
      def duplicate_frame
        return if @frames.size >= Diagram::MAX_FRAMES

        push_undo
        @frames.insert(@frame_index + 1, deep_copy(frame))
        @frame_index += 1
        @selected = nil
      end

      def delete_frame
        push_undo
        @frames.delete_at(@frame_index)
        @frames << blank_frame if @frames.empty?
        @frame_index = [ @frame_index, @frames.size - 1 ].min
        @selected = nil
      end

      def frame_title(title)
        frame["title"] = title.to_s[0, Diagram::MAX_TITLE].to_s
      end

      # Подписи раздаём по порядку: игроки буквами, соперники цифрами. Остальные
      # фигуры узнаются по форме, подпись им только мешает.
      #
      # Ищем первую свободную подпись, а не считаем фигуры: после удаления
      # счётчик снова выдал бы уже занятую букву — убрали A из [A, B], и
      # следующий игрок тоже стал бы B.
      def next_label(kind)
        candidates =
          case kind
          when "player" then PLAYER_LABELS
          when "opponent" then OPPONENT_LABELS
          else return ""
          end

        used = frame["items"].filter_map { |item| item["label"] if item["kind"] == kind }
        candidates.find { |label| !used.include?(label) }.to_s
      end

      # Индекс фигуры под пальцем считает браузер, поэтому проверяем: попадание
      # мимо кадра выделять нечего.
      def item_index(index)
        return nil unless index.is_a?(Integer) || (index.is_a?(String) && index.match?(/\A\d+\z/))

        index = index.to_i
        index if (0...frame["items"].size).cover?(index)
      end

      def frame_from(raw)
        raw = {} unless raw.is_a?(Hash)

        {
          "title" => raw["title"].to_s,
          "items" => raw["items"].is_a?(Array) ? raw["items"] : [],
          "arrows" => raw["arrows"].is_a?(Array) ? raw["arrows"] : []
        }
      end

      def blank_frame(title = "")
        { "title" => title, "items" => [], "arrows" => [] }
      end

      def deep_copy(value)
        JSON.parse(JSON.generate(value))
      end

      def push_undo
        @undo << JSON.generate(@frames)
        @undo.shift if @undo.size > UNDO_LIMIT
      end
    end
  end
end
