class TrainingBlock
  class Diagram
    # Исходник схемы для браузера: те же два файла, что грузит Rails, склеенные
    # в одну строку для ruby.wasm.
    #
    # Смысл эксперимента ровно в этом — не «портировать» правила разбора схемы в
    # JS, а отдать браузеру сам файл. Расходиться нечему: правило одно и живёт в
    # одном месте.
    module Source
      FILES = [
        File.expand_path("../diagram.rb", __dir__),
        File.expand_path("editor.rb", __dir__)
      ].freeze

      # Меняется только вместе с деплоем, поэтому читаем с диска один раз.
      # В development константу сбрасывает перезагрузка кода.
      def self.call
        @call ||= FILES.map { |path| File.read(path) }.join("\n")
      end
    end
  end
end
