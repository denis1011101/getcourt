require "cgi"
require "tempfile"

module Telegram
  module Helpers
    class GameCardRenderer
      WIDTH = 600
      HEIGHT = 315

      class << self
        def render(game, locale: Telegram::I18n::DEFAULT_LOCALE)
          png = Tempfile.new([ "game-share-card-", ".png" ], Rails.root.join("tmp"))
          png.close

          render_image(svg_markup(game, locale: locale)).write_to_file(png.path)
          png.path
        end

        private

        def svg_markup(game, locale:)
          title = "#{Telegram::Helpers::GameFormatting.game_title(game) || 'Game'} ##{game.id}"
          coach = coach_value(game, locale)
          datetime = Telegram::Helpers::GameFormatting.game_datetime(game).presence || "-"
          players = players_value(game, locale)
          court = game.court&.name.presence || "-"
          owner = owner_value(game)

          <<~SVG
            <svg width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <linearGradient id="bg" x1="0" y1="0" x2="#{WIDTH}" y2="#{HEIGHT}" gradientUnits="userSpaceOnUse">
                  <stop stop-color="#1E1B4B"/>
                  <stop offset="0.5" stop-color="#312E81"/>
                  <stop offset="1" stop-color="#86198F"/>
                </linearGradient>
                <linearGradient id="ov" x1="0" y1="0" x2="#{WIDTH}" y2="#{HEIGHT}" gradientUnits="userSpaceOnUse">
                  <stop stop-color="#FFFFFF" stop-opacity="0.08"/>
                  <stop offset="0.5" stop-color="#818CF8" stop-opacity="0.05"/>
                  <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
                </linearGradient>
                <radialGradient id="g1" cx="0.9" cy="0.1" r="0.55" gradientUnits="objectBoundingBox">
                  <stop stop-color="#A855F7" stop-opacity="0.35"/>
                  <stop offset="1" stop-color="#A855F7" stop-opacity="0"/>
                </radialGradient>
                <radialGradient id="g2" cx="0.1" cy="0.95" r="0.5" gradientUnits="objectBoundingBox">
                  <stop stop-color="#6366F1" stop-opacity="0.25"/>
                  <stop offset="1" stop-color="#6366F1" stop-opacity="0"/>
                </radialGradient>
                <linearGradient id="lt" x1="0" y1="0" x2="0" y2="1" gradientUnits="objectBoundingBox">
                  <stop stop-color="#FFFFFF"/>
                  <stop offset="1" stop-color="#C4B5FD"/>
                </linearGradient>
              </defs>

              <!-- Background fills whole rect, no rounding = no white corners -->
              <rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#bg)"/>
              <rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#ov)"/>
              <rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#g1)"/>
              <rect width="#{WIDTH}" height="#{HEIGHT}" fill="url(#g2)"/>

              <!-- Tennis court (large, right side) -->
              <g transform="translate(#{WIDTH - 240} #{(HEIGHT - 260) / 2}) scale(1.6)" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="1.2" fill="none">
                <rect x="4" y="4" width="112" height="152" rx="2"/>
                <line x1="18" y1="4" x2="18" y2="156"/>
                <line x1="102" y1="4" x2="102" y2="156"/>
                <line x1="4" y1="80" x2="116" y2="80"/>
                <line x1="18" y1="52" x2="102" y2="52"/>
                <line x1="18" y1="108" x2="102" y2="108"/>
                <line x1="60" y1="52" x2="60" y2="108"/>
                <line x1="56" y1="4" x2="64" y2="4"/>
                <line x1="56" y1="156" x2="64" y2="156"/>
              </g>

              <!-- Title -->
              <text x="28" y="44" fill="#FFFFFF" font-size="22" font-weight="700" font-family="DejaVu Sans, Arial, sans-serif">#{esc(title)}</text>

              <!-- Coach -->
              <text x="28" y="72" fill="#FFFFFF" fill-opacity="0.75" font-size="13" font-weight="400" font-family="DejaVu Sans, Arial, sans-serif">#{esc(coach)}</text>

              <!-- When -->
              <text x="28" y="116" fill="#FFFFFF" font-size="16" font-weight="600" font-family="DejaVu Sans, Arial, sans-serif">#{esc(Telegram::I18n.t(:when_label, locale: locale, datetime: datetime))}</text>

              <!-- Players -->
              <text x="28" y="148" fill="#FFFFFF" font-size="16" font-weight="600" font-family="DejaVu Sans, Arial, sans-serif">#{esc(players)}</text>

              <!-- Court -->
              <text x="28" y="180" fill="#FFFFFF" font-size="16" font-weight="600" font-family="DejaVu Sans, Arial, sans-serif">#{esc(Telegram::I18n.t(:court_label, locale: locale, name: court))}</text>

              <!-- Owner -->
              <text x="28" y="258" fill="#C4B5FD" font-size="15" font-weight="600" font-family="DejaVu Sans, Arial, sans-serif">#{esc(Telegram::I18n.t(:owner, locale: locale, name: owner))}</text>

              <!-- Logo: Get / Court in top-right corner -->
              <text x="#{WIDTH - 78}" y="32" fill="url(#lt)" font-size="18" font-weight="700" font-family="DejaVu Sans, Arial, sans-serif" opacity="0.8">Get</text>
              <text x="#{WIDTH - 78}" y="54" fill="url(#lt)" font-size="18" font-weight="700" font-family="DejaVu Sans, Arial, sans-serif" opacity="0.8">Court</text>
            </svg>
          SVG
        end

        def coach_value(game, locale)
          if game.respond_to?(:with_coach?) && game.with_coach?
            Telegram::I18n.t(:coach_label, locale: locale, value: Telegram::I18n.t(:coach_with, locale: locale))
          elsif game.respond_to?(:needs_coach?) && game.needs_coach?
            Telegram::I18n.t(:coach_label, locale: locale, value: Telegram::I18n.t(:coach_need, locale: locale))
          else
            Telegram::I18n.t(:coach_label, locale: locale, value: Telegram::I18n.t(:coach_no, locale: locale))
          end
        end

        def players_value(game, locale)
          approved_count =
            if game.respond_to?(:participations)
              game.participations.respond_to?(:approved) ? game.participations.approved.size : game.participations.size
            else
              0
            end
          capacity = (game.respond_to?(:players_count) && game.players_count.to_i > 0) ? game.players_count.to_i : "?"
          Telegram::I18n.t(:players, locale: locale, count: approved_count, capacity: capacity)
        end

        def owner_value(game)
          user = User.find_by(id: game.user_id)
          Telegram::Helpers::UserLookup.display_name(user, fallback: user&.telegram_chat_id || "—")
        end

        def esc(value)
          CGI.escapeHTML(value.to_s)
        end

        def render_image(svg)
          load_vips!
          Vips::Image.svgload_buffer(svg, dpi: 72)
        end

        def load_vips!
          require "vips" unless defined?(Vips::Image)
        end
      end
    end
  end
end
