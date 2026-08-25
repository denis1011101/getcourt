# frozen_string_literal: true

require "cgi"

module Games
  # Карточка игры картинкой. Макет повторяет `games/_card`: человек делится тем же,
  # что видит в списке игр, поэтому все метки, комментарий и счётчик мест на месте.
  class ShareCardRenderer
    CANVAS_WIDTH  = 640
    CARD_MARGIN   = 20
    CARD_PADDING  = 20
    CARD_WIDTH    = CANVAS_WIDTH - CARD_MARGIN * 2
    CONTENT_WIDTH = CARD_WIDTH - CARD_PADDING * 2
    ACCENT_HEIGHT = 4
    BRAND_HEIGHT  = 26
    # Логические координаты пишем в единицах CSS, а рисуем вдвое крупнее: в ленте
    # мессенджера картинка не должна выглядеть мыльной.
    RENDER_DPI = 144

    FONT_FAMILY  = "DejaVu Sans, Arial, sans-serif"
    MEASURE_FONT = "DejaVu Sans"

    PAGE_BG      = "#0F172A"
    CARD_BG      = "#1E293B"
    CARD_BORDER  = "#FFFFFF"
    TITLE_COLOR  = "#F1F5F9"
    MUTED_COLOR  = "#94A3B8"
    DATE_BG      = "#6366F1"
    DATE_COLOR   = "#A5B4FC"
    OPEN_COLOR   = "#4ADE80"
    FULL_COLOR   = "#F87171"
    BRAND_COLOR  = "#475569"

    SPORT_ACCENTS = {
      "tennis" => "#22C55E",
      "padel" => "#3B82F6",
      "table_tennis" => "#F97316",
      "squash" => "#A855F7"
    }.freeze
    DEFAULT_ACCENT = "#6366F1"

    # Тёмные варианты тех же pill'ов, что в списке игр.
    BADGE_STYLES = {
      sport: { fill: "#334155", fill_opacity: 1, color: "#F1F5F9" },
      skill: { fill: "#F59E0B", fill_opacity: 0.15, color: "#FDE68A" },
      surface: { fill: "#F59E0B", fill_opacity: 0.15, color: "#FCD34D" },
      environment: { fill: "#0EA5E9", fill_opacity: 0.15, color: "#7DD3FC" },
      training: { fill: "#8B5CF6", fill_opacity: 0.15, color: "#DDD6FE" },
      coach: { fill: "#3B82F6", fill_opacity: 0.15, color: "#BFDBFE" },
      weekly: { fill: "#A855F7", fill_opacity: 0.15, color: "#E9D5FF" },
      player_search: { fill: "#F43F5E", fill_opacity: 0.15, color: "#FECDD3" },
      tournament: { fill: "#A855F7", fill_opacity: 0.15, color: "#E9D5FF" },
      weather: { fill: "#334155", fill_opacity: 1, color: "#F1F5F9" }
    }.freeze

    BADGE_HEIGHT   = 24
    BADGE_FONT     = 13
    BADGE_PADDING  = 10
    BADGE_GAP      = 6
    ICON_WIDTH     = 19

    # Иконку погоды рисуем вектором: эмодзи на сервере рендерится как «тофу»,
    # цветного шрифта там нет. Вид определяем через тот же Weather::Icons.
    WEATHER_ICONS = {
      "⛈️" => :thunder,
      "❄️" => :snow,
      "🌧️" => :rain,
      "💨" => :wind,
      "⛅" => :cloud,
      "☀️" => :sun
    }.freeze

    class << self
      def render_data(game, locale: I18n.locale)
        Images::SvgRasterizer.render_png(svg_markup(game, locale: locale), dpi: RENDER_DPI)
      end

      private

      def svg_markup(game, locale:)
        I18n.with_locale(locale) { build_svg(game) }
      end

      def build_svg(game)
        # Замеры ширины живут ровно один рендер: на долгих потоках Puma общий кэш
        # копил бы каждое название корта и каждый обрывок комментария.
        Thread.current[:share_card_text_widths] = {}
        body = []
        x = CARD_MARGIN + CARD_PADDING
        y = CARD_MARGIN + ACCENT_HEIGHT + CARD_PADDING

        y = draw_datetime(body, game, x, y)
        y = draw_title(body, game, x, y)
        y = draw_badges(body, game, x, y)
        y = draw_tournament(body, game, x, y)
        y = draw_comment(body, game, x, y)
        y = draw_players(body, game, x, y)

        card_height = y + CARD_PADDING - CARD_MARGIN
        height = CARD_MARGIN * 2 + card_height + BRAND_HEIGHT

        <<~SVG
          <svg width="#{CANVAS_WIDTH}" height="#{height}" viewBox="0 0 #{CANVAS_WIDTH} #{height}" xmlns="http://www.w3.org/2000/svg">
            <defs>
              <clipPath id="card">
                <rect x="#{CARD_MARGIN}" y="#{CARD_MARGIN}" width="#{CARD_WIDTH}" height="#{card_height}" rx="12"/>
              </clipPath>
            </defs>
            <rect width="#{CANVAS_WIDTH}" height="#{height}" fill="#{PAGE_BG}"/>
            <rect x="#{CARD_MARGIN}" y="#{CARD_MARGIN}" width="#{CARD_WIDTH}" height="#{card_height}" rx="12" fill="#{CARD_BG}" stroke="#{CARD_BORDER}" stroke-opacity="0.1"/>
            <rect x="#{CARD_MARGIN}" y="#{CARD_MARGIN}" width="#{CARD_WIDTH}" height="#{ACCENT_HEIGHT}" fill="#{accent_color(game)}" clip-path="url(#card)"/>
            #{body.join("\n  ")}
            <text x="#{CANVAS_WIDTH / 2}" y="#{height - 10}" fill="#{BRAND_COLOR}" font-size="12" font-family="#{FONT_FAMILY}" text-anchor="middle">getcourt.co</text>
          </svg>
        SVG
      ensure
        Thread.current[:share_card_text_widths] = nil
      end

      # --- Блоки карточки -------------------------------------------------

      def draw_datetime(body, game, x, y)
        display_date = game.display_date_for_show || game.date
        game_time = game.next_time || game.time

        body << rounded_rect(x, y, 44, 44, 10, DATE_BG, 0.15)
        if display_date
          body << text(x + 22, y + 17, display_date.strftime("%b").upcase, size: 11, weight: 500, color: DATE_COLOR, anchor: "middle")
          body << text(x + 22, y + 35, display_date.strftime("%d"), size: 18, weight: 700, color: DATE_COLOR, anchor: "middle")
        else
          body << calendar_icon(x + 12, y + 12, DATE_COLOR)
        end

        text_x = x + 56
        body << text(text_x, y + 20, display_date.strftime("%A"), size: 15, weight: 500, color: TITLE_COLOR) if display_date
        body << text(text_x, y + 38, game_time.strftime("%I:%M %p"), size: 13, color: MUTED_COLOR) if game_time

        y + 44 + 14
      end

      def draw_title(body, game, x, y)
        lines = wrap(game.court&.name.to_s, CONTENT_WIDTH, size: 20, weight: 700, max_lines: 2)
        lines.each_with_index do |line, i|
          body << text(x, y + 18 + i * 26, line, size: 20, weight: 700, color: TITLE_COLOR)
        end

        y + lines.size * 26 + 8
      end

      def draw_badges(body, game, x, y)
        badges = badges_for(game)
        return y if badges.empty?

        cursor_x = x
        rows = 1
        badges.each do |badge|
          width = badge_width(badge)
          if cursor_x + width > x + CONTENT_WIDTH && cursor_x > x
            cursor_x = x
            rows += 1
          end
          draw_badge(body, badge, cursor_x, y + (rows - 1) * (BADGE_HEIGHT + BADGE_GAP))
          cursor_x += width + BADGE_GAP
        end

        y + rows * BADGE_HEIGHT + (rows - 1) * BADGE_GAP + 12
      end

      def draw_tournament(body, game, x, y)
        tournament = game.tournament
        return y if tournament.blank?

        badge = { style: :tournament, text: I18n.t("games.show.tournament", default: "Tournament") }
        draw_badge(body, badge, x, y)

        name_x = x + badge_width(badge) + 8
        name = truncate_to(tournament.name.presence || "##{tournament.id}", CONTENT_WIDTH - (name_x - x), size: 13, weight: 500)
        body << text(name_x, y + 16, name, size: 13, weight: 500, color: "#818CF8")

        y + BADGE_HEIGHT + 12
      end

      def draw_comment(body, game, x, y)
        comment = game.comment.to_s.squish
        return y if comment.blank?

        lines = wrap(comment, CONTENT_WIDTH, size: 13, max_lines: 3)
        lines.each_with_index do |line, i|
          body << text(x, y + 11 + i * 18, line, size: 13, color: MUTED_COLOR)
        end

        y + lines.size * 18 + 10
      end

      def draw_players(body, game, x, y)
        taken, required = participation_counts(game)
        spots_left = required - taken

        dot_x = x
        [ taken, 4 ].min.times do
          body << player_dot(dot_x, y)
          dot_x += 20
        end
        if spots_left.positive?
          [ spots_left, 3 ].min.times do
            body << empty_dot(dot_x, y)
            dot_x += 20
          end
        end

        counter_x = dot_x + (dot_x > x ? 10 : 0)
        body << text(counter_x, y + 17, "#{taken}/#{required}", size: 13, color: MUTED_COLOR)

        if spots_left.positive?
          label = I18n.t("games.card.spots_left", count: spots_left)
          color = OPEN_COLOR
        else
          label = I18n.t("games.card.full")
          color = FULL_COLOR
        end
        body << text(x + CONTENT_WIDTH, y + 17, label, size: 13, weight: 500, color: color, anchor: "end")

        y + 24
      end

      # --- Данные ---------------------------------------------------------

      def badges_for(game)
        badges = []
        if game.sport.present?
          badges << { style: :sport, text: I18n.t("games.sports.#{game.sport.to_s.parameterize(separator: '_')}", default: game.sport.to_s.titleize) }
        end
        if game.skill_level.present?
          badges << { style: :skill, text: game.skill_level.to_s.titleize }
        end
        badges << { style: :surface, text: game.surface_label } if game.surface_label.present?
        badges << { style: :environment, text: game.environment_label } if game.environment_label.present?
        badges << { style: :training, text: I18n.t("games.badges.training") } if game.training?
        badges << { style: :coach, text: I18n.t("games.badges.coach") } if game.with_coach?
        badges << { style: :weekly, text: I18n.t("games.badges.weekly") } if game.recurring?
        badges << { style: :player_search, text: I18n.t("games.badges.player_search") } if game.urgent_player_search?
        weather = weather_badge(game)
        badges << weather if weather

        badges
      end

      def weather_badge(game)
        return nil unless game.court&.coordinates_pair && game.environment.to_s != "indoor"

        reading = Weather::GoogleForecast.for_game(game, timeout: 2)
        return nil unless reading

        label = "#{reading.temperature_c.round}°"
        label += " · #{reading.precipitation_percent}%" if reading.precipitation_percent.to_i >= 30
        { style: :weather, text: label, icon: WEATHER_ICONS[Weather::Icons.for(reading.condition_type)] || :thermometer }
      rescue => e
        Rails.logger.warn("[ShareCard] weather skipped for Game##{game.id}: #{e.class} #{e.message}")
        nil
      end

      def participation_counts(game)
        participations = game.participations.loaded? ? game.participations.target : game.participations.to_a
        taken = participations.count(&:approved?)
        required = game.players_count.to_i.positive? ? game.players_count.to_i : 4
        [ taken, required ]
      end

      def accent_color(game)
        SPORT_ACCENTS[game.sport.to_s.downcase] || DEFAULT_ACCENT
      end

      # --- Примитивы ------------------------------------------------------

      def draw_badge(body, badge, x, y)
        style = BADGE_STYLES.fetch(badge[:style])
        body << rounded_rect(x, y, badge_width(badge), BADGE_HEIGHT, BADGE_HEIGHT / 2, style[:fill], style[:fill_opacity])

        text_x = x + BADGE_PADDING
        if badge[:icon]
          body << weather_icon(badge[:icon], x + BADGE_PADDING, y + 5, style[:color])
          text_x += ICON_WIDTH
        end
        body << text(text_x, y + 16, badge[:text], size: BADGE_FONT, weight: 500, color: style[:color])
      end

      def badge_width(badge)
        width = text_width(badge[:text], size: BADGE_FONT, weight: 500) + BADGE_PADDING * 2
        width += ICON_WIDTH if badge[:icon]
        width
      end

      def player_dot(x, y)
        <<~SVG.strip
          <g><circle cx="#{x + 12}" cy="#{y + 12}" r="11" fill="#{DATE_BG}" fill-opacity="0.2" stroke="#{CARD_BG}" stroke-width="2"/>
            <g transform="translate(#{x + 6} #{y + 6}) scale(0.6)" fill="#818CF8"><path d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z"/></g></g>
        SVG
      end

      def empty_dot(x, y)
        <<~SVG.strip
          <g><circle cx="#{x + 12}" cy="#{y + 12}" r="11" fill="#334155" stroke="#64748B" stroke-width="2" stroke-dasharray="3 3"/>
            <path d="M#{x + 12} #{y + 8}V#{y + 16}M#{x + 8} #{y + 12}H#{x + 16}" stroke="#94A3B8" stroke-width="1.6" stroke-linecap="round"/></g>
        SVG
      end

      def calendar_icon(x, y, color)
        <<~SVG.strip
          <g transform="translate(#{x} #{y}) scale(0.83)" fill="none" stroke="#{color}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25"/></g>
        SVG
      end

      def weather_icon(kind, x, y, color)
        shape =
          case kind
          when :sun
            %(<circle cx="7" cy="7" r="3.2" fill="#{color}"/>) +
              (0..7).map { |i|
                angle = i * Math::PI / 4
                %(<line x1="#{(7 + 5 * Math.cos(angle)).round(2)}" y1="#{(7 + 5 * Math.sin(angle)).round(2)}" x2="#{(7 + 6.5 * Math.cos(angle)).round(2)}" y2="#{(7 + 6.5 * Math.sin(angle)).round(2)}" stroke="#{color}" stroke-width="1.4" stroke-linecap="round"/>)
              }.join
          when :cloud
            cloud_shape(color)
          when :rain
            cloud_shape(color, cy: 4.5) +
              %(<line x1="4.5" y1="10.5" x2="3.5" y2="13.5" stroke="#{color}" stroke-width="1.4" stroke-linecap="round"/>) +
              %(<line x1="8.5" y1="10.5" x2="7.5" y2="13.5" stroke="#{color}" stroke-width="1.4" stroke-linecap="round"/>) +
              %(<line x1="12.5" y1="10.5" x2="11.5" y2="13.5" stroke="#{color}" stroke-width="1.4" stroke-linecap="round"/>)
          when :snow
            [ 0, 60, 120 ].map { |deg|
              %(<line x1="7" y1="1.5" x2="7" y2="12.5" stroke="#{color}" stroke-width="1.4" stroke-linecap="round" transform="rotate(#{deg} 7 7)"/>)
            }.join
          when :thunder
            cloud_shape(color, cy: 4.5) +
              %(<path d="M8 10l-3 4h2.4l-1.4 3.2 4-4.6H7.6z" fill="#{color}"/>)
          when :wind
            [ [ 4, 10 ], [ 7.2, 12.5 ], [ 10.4, 8.5 ] ].map { |cy, x2|
              %(<line x1="1.5" y1="#{cy}" x2="#{x2}" y2="#{cy}" stroke="#{color}" stroke-width="1.4" stroke-linecap="round"/>)
            }.join
          else
            %(<path d="M7 2.5v6.2" stroke="#{color}" stroke-width="1.6" stroke-linecap="round"/><circle cx="7" cy="10.8" r="2.4" fill="#{color}"/>)
          end

        %(<g transform="translate(#{x} #{y})">#{shape}</g>)
      end

      def cloud_shape(color, cy: 7)
        %(<circle cx="4.8" cy="#{cy + 0.5}" r="3" fill="#{color}"/>) +
          %(<circle cx="9" cy="#{cy - 0.5}" r="3.8" fill="#{color}"/>) +
          %(<rect x="4" y="#{cy}" width="8" height="3.4" rx="1.7" fill="#{color}"/>)
      end

      def rounded_rect(x, y, width, height, radius, fill, fill_opacity = 1)
        %(<rect x="#{x}" y="#{y}" width="#{width.round(2)}" height="#{height}" rx="#{radius}" fill="#{fill}" fill-opacity="#{fill_opacity}"/>)
      end

      def text(x, y, value, size:, color:, weight: 400, anchor: nil)
        attrs = +%(x="#{x.round(2)}" y="#{y}" fill="#{color}" font-size="#{size}" font-weight="#{weight}" font-family="#{FONT_FAMILY}")
        attrs << %( text-anchor="#{anchor}") if anchor
        %(<text #{attrs}>#{CGI.escapeHTML(value.to_s)}</text>)
      end

      # --- Текст ----------------------------------------------------------

      def wrap(value, max_width, size:, max_lines:, weight: 400)
        words = value.to_s.split(/\s+/).reject(&:empty?)
        return [] if words.empty?

        lines = []
        current = nil
        leftover = false

        words.each do |word|
          candidate = current ? "#{current} #{word}" : word
          if current.nil? || text_width(candidate, size: size, weight: weight) <= max_width
            current = candidate
            next
          end

          lines << current
          if lines.size >= max_lines
            current = nil
            leftover = true
            break
          end
          current = word
        end

        lines << current if current && lines.size < max_lines
        lines[-1] = "#{lines.last}…" if leftover && lines.any?
        lines.map { |line| truncate_to(line, max_width, size: size, weight: weight) }
      end

      # Режем бинарным поиском: посимвольный перебор на длинном слове без пробелов
      # обошёлся бы в сотни замеров подряд.
      def truncate_to(value, max_width, size:, weight: 400)
        value = value.to_s
        return value if text_width(value, size: size, weight: weight) <= max_width

        low = 0
        high = value.length - 1
        while low < high
          mid = (low + high + 1) / 2
          if text_width("#{value[0, mid]}…", size: size, weight: weight) <= max_width
            low = mid
          else
            high = mid - 1
          end
        end

        "#{value[0, low]}…"
      end

      # Ширину меряем самим libvips: pill'ы обязаны сходиться с текстом, а на глаз
      # кириллица и латиница считаются по-разному.
      def text_width(value, size:, weight: 400)
        return 0 if value.to_s.empty?

        key = [ value, size, weight ]
        cache = (Thread.current[:share_card_text_widths] ||= {})
        cache[key] ||= begin
          require "vips" unless defined?(Vips::Image)
          font = weight.to_i >= 600 ? "#{MEASURE_FONT} Bold #{size}" : "#{MEASURE_FONT} #{size}"
          Vips::Image.text(value.to_s, font: font, dpi: 72).width
        rescue => e
          Rails.logger.warn("[ShareCard] text measure failed: #{e.class} #{e.message}")
          (value.to_s.length * size * 0.55).round
        end
      end
    end
  end
end
