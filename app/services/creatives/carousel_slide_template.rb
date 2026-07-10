# frozen_string_literal: true

require 'cgi'

module Creatives
  # Renders one branded carousel slide as a self-contained HTML document for the
  # headless renderer (Vendors::Render::Html). No external fonts/assets — brand
  # colors, @handle, avatar/logo and any image are inlined, so the render is
  # deterministic and offline.
  #
  # Two layouts: a full-bleed image slide (when an image data URI is supplied)
  # and a typographic slide (the default for viral carousels).
  class CarouselSlideTemplate
    def self.render(...) = new(...).render

    # slide: { "role", "headline", "body" } from Prompts::CarouselCopy
    def initialize(slide:, index:, total:, width:, height:, primary:, secondary:,
                   carousel_style: 'gradient', handle: nil, brand_name: nil,
                   avatar_uri: nil, logo_uri: nil, image_uri: nil)
      @slide      = slide || {}
      @index      = index
      @total      = total
      @width      = width.to_i
      @height     = height.to_i
      @primary    = primary
      @secondary  = secondary
      @style      = carousel_style.to_s
      @handle     = handle
      @brand_name = brand_name
      @avatar_uri = avatar_uri
      @logo_uri   = logo_uri
      @image_uri  = image_uri
    end

    def render
      <<~HTML
        <!doctype html>
        <html><head><meta charset="utf-8"><style>#{css}</style></head>
        <body>
          <div class="slide #{image? ? 'has-image' : 'plain'}">
            #{image? ? image_layer : ''}
            <div class="overlay">
              <header class="top">
                <div class="brand">
                  #{avatar_html}
                  <div class="who">
                    <span class="name">#{esc(@brand_name)}</span>
                    #{handle_html}
                  </div>
                </div>
                <span class="counter">#{@index}/#{@total}</span>
              </header>

              <main class="body">
                #{cta? ? "<div class=\"kicker\">#{esc('Próximo passo')}</div>" : ''}
                <h1 class="headline">#{esc(@slide['headline'])}</h1>
                #{body_html}
              </main>

              <footer class="bottom">
                #{cta? ? "<span class=\"swipe\">#{esc('Salve e compartilhe')}</span>" : "<span class=\"swipe\">#{esc('Arraste →')}</span>"}
                #{logo_html}
              </footer>
            </div>
          </div>
        </body></html>
      HTML
    end

    private

    def role  = @slide['role'].to_s
    def cta?  = role == 'cta' || @index == @total
    def hook? = role == 'hook' || @index == 1
    def image? = @image_uri.present?
    def white? = @style == 'white'

    def body_html
      return '' if @slide['body'].to_s.strip.blank?

      %(<p class="text">#{esc(@slide['body'])}</p>)
    end

    # Always render an avatar: the brand's creator avatar when present, otherwise
    # an initials chip — the header is always avatar + name + @handle.
    def avatar_html
      return %(<img class="avatar" src="#{@avatar_uri}" alt="">) if @avatar_uri.present?

      %(<div class="avatar initials">#{esc(initials)}</div>)
    end

    def handle_html
      return '' if @handle.blank?

      %(<span class="handle">@#{esc(@handle.to_s.sub(/\A@/, ''))}</span>)
    end

    def initials
      @brand_name.to_s.split(/\s+/).reject(&:empty?).first(2).map { |w| w[0] }.join.upcase.presence || '•'
    end

    def logo_html
      return '' if @logo_uri.blank?

      %(<img class="logo" src="#{@logo_uri}" alt="">)
    end

    # Image style shows the picked photo CLEAN — no darkening lens. Copy stays
    # legible via per-element text-shadows (see `.has-image` rules), not a scrim.
    def image_layer
      %(<div class="image" style="background-image:url('#{@image_uri}')"></div>)
    end

    def css
      hl_size = if hook?
                  92
                else
                  (cta? ? 84 : 72)
                end
      <<~CSS
        * { margin:0; padding:0; box-sizing:border-box; }
        html,body { width:#{@width}px; height:#{@height}px; }
        .slide {
          position:relative; width:#{@width}px; height:#{@height}px; overflow:hidden;
          font-family: -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          color:#fff;
          background:
            radial-gradient(120% 120% at 0% 0%, #{@primary} 0%, #{shade(@primary, -28)} 70%);
        }
        .image {
          position:absolute; inset:0; background-size:cover; background-position:center;
        }
        .overlay {
          position:absolute; inset:0; display:flex; flex-direction:column;
          padding:120px 64px 160px;
        }
        .top { display:flex; align-items:center; justify-content:space-between; }
        .brand { display:flex; align-items:center; gap:20px; }
        .avatar { width:96px; height:96px; border-radius:50%; object-fit:cover;
          border:4px solid rgba(255,255,255,.9); flex:none; }
        .avatar.initials { display:flex; align-items:center; justify-content:center;
          background:#{@secondary}; color:#fff; font-size:40px; font-weight:800; }
        .who { display:flex; flex-direction:column; line-height:1.15; }
        .name { font-size:36px; font-weight:800; letter-spacing:.2px; }
        .handle { font-size:28px; font-weight:600; opacity:.82; }
        .counter { font-size:30px; font-weight:700; opacity:.8;
          background:rgba(255,255,255,.16); padding:8px 20px; border-radius:999px; }
        .body { flex:1; display:flex; flex-direction:column; justify-content:center; gap:32px; }
        .kicker { display:inline-block; align-self:flex-start; font-size:30px; font-weight:800;
          text-transform:uppercase; letter-spacing:2px; color:#{@secondary}; }
        .headline { font-size:#{hl_size}px; font-weight:800; line-height:1.05;
          text-wrap:balance; max-width:18ch; }
        .text { font-size:44px; line-height:1.4; opacity:.92; max-width:24ch; }
        .bottom { display:flex; align-items:center; justify-content:space-between; }
        .swipe { font-size:30px; font-weight:700; opacity:.85;
          border-top:4px solid #{@secondary}; padding-top:16px; }
        .logo { height:64px; width:auto; object-fit:contain; opacity:.95; }
        /* No scrim on image slides — keep copy readable with text-shadows alone. */
        .has-image .name, .has-image .handle, .has-image .counter,
        .has-image .kicker, .has-image .text, .has-image .swipe {
          text-shadow:0 2px 12px rgba(0,0,0,.55); }
        .has-image .headline { text-shadow:0 4px 24px rgba(0,0,0,.65); }
        .plain .headline::after { content:""; display:block; width:140px; height:10px;
          margin-top:28px; border-radius:999px; background:#{@secondary}; }
        #{white_css}
      CSS
    end

    # White-background variant: only the typographic (`.plain`) slides flip to a
    # white background with dark ink; full-bleed image slides keep their dark scrim
    # and white text. Emitted last so it overrides the gradient defaults; empty
    # (byte-identical output) for the default gradient style.
    def white_css
      return '' unless white?

      <<~CSS.chomp
        .plain { background:#ffffff; color:#18161d; }
        .plain .counter { background:rgba(0,0,0,.05); color:#18161d; }
        .plain .avatar { border-color:rgba(0,0,0,.10); }
      CSS
    end

    def esc(value) = CGI.escapeHTML(value.to_s)

    # Darken (or lighten) a #rrggbb hex by `pct` percent. Returns the input on
    # any non-hex value so brand colors are always safe to drop into CSS.
    def shade(hex, pct)
      m = hex.to_s.strip.match(/\A#?([0-9a-fA-F]{6})\z/)
      return hex unless m

      rgb = m[1].scan(/../).map { |c| c.to_i(16) }
      adj = rgb.map do |c|
        v = c + (255 * pct / 100.0)
        v.clamp(0, 255).round
      end
      format('#%02x%02x%02x', *adj)
    end
  end
end
