# frozen_string_literal: true

require "open3"

module Images
  # Растеризует наш собственный SVG в PNG. Работу делает отдельный процесс
  # (`script/svg_to_png.rb`): в приложении загрузчик SVG закрыт Active Storage,
  # и открывать его в веб-процессе, который рядом обрабатывает чужие загрузки, нельзя.
  module SvgRasterizer
    class Error < StandardError; end

    SCRIPT = Rails.root.join("script/svg_to_png.rb").to_s

    def self.render_png(svg, dpi:)
      out, err, status = Open3.capture3(child_env, RbConfig.ruby, SCRIPT, dpi.to_s, stdin_data: svg, binmode: true)
      raise Error, "svg render failed (#{status.exitstatus}): #{err.to_s.lines.last&.strip}" unless status.success?

      out
    end

    # Дочернему процессу нужен ruby-vips из бандла — bundler в родителе уже прописан
    # в окружении, но под systemd переменных может не быть, поэтому подстраховываемся.
    def self.child_env
      {
        "BUNDLE_GEMFILE" => ENV["BUNDLE_GEMFILE"].presence || Rails.root.join("Gemfile").to_s,
        "RUBYOPT" => [ ENV["RUBYOPT"], "-rbundler/setup" ].compact_blank.join(" ")
      }
    end
    private_class_method :child_env
  end
end
