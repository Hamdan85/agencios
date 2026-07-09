# frozen_string_literal: true

require 'ferrum'

module Vendors
  # Headless HTML→PNG renderer (Ferrum / Chromium over CDP). Used to compose
  # branded carousel slides from HTML+CSS instead of AI raster images.
  #
  # The Chromium binary is auto-detected; override with ENV FERRUM_BROWSER_PATH
  # (or CHROME_PATH). In production the runtime image must ship chromium.
  module Render
    class Html
      include Launcher

      class RenderError < StandardError; end

      DEFAULT_SELECTOR = '.slide'

      def self.call(...) = new(...).call

      # Load a URL in the headless browser and return the rendered body text —
      # the JS-site fallback for Vendors::Web::Reader.
      def self.page_text(url:)
        new(width: 1280, height: 1600).fetch_text(url)
      end

      def fetch_text(url)
        browser = launch_browser(window_size: [@width, @height], browser_options: { 'hide-scrollbars' => nil })
        begin
          page = browser.create_page
          page.go_to(url)
          begin
            page.network.wait_for_idle(timeout: 12)
          rescue StandardError
            nil
          end
          page.evaluate("document.body ? document.body.innerText : ''").to_s
        ensure
          browser&.quit
        end
      rescue Ferrum::Error, Errno::ENOENT => e
        raise RenderError, "Falha ao ler página (Chromium): #{e.message}"
      end

      # Render many HTML documents in one browser session. Each item is rendered
      # to PNG bytes, cropped to `selector`. Returns an array of binary strings.
      def self.batch(htmls:, width:, height:, selector: DEFAULT_SELECTOR)
        new(width: width, height: height, selector: selector).render_many(htmls)
      end

      def initialize(width:, height:, html: nil, selector: DEFAULT_SELECTOR)
        @html     = html
        @width    = width.to_i
        @height   = height.to_i
        @selector = selector
      end

      def call
        render_many([@html]).first
      end

      def render_many(htmls)
        browser = launch_browser(window_size: [@width, @height], browser_options: { 'hide-scrollbars' => nil })
        begin
          htmls.map { |html| render_one(browser, html) }
        ensure
          browser&.quit
        end
      rescue Ferrum::Error, Errno::ENOENT => e
        raise RenderError, "Falha ao renderizar HTML (Chromium): #{e.message}"
      end

      private

      def render_one(browser, html)
        page = browser.create_page
        page.set_viewport(width: @width, height: @height)
        page.content = html
        wait_for_assets(page)
        png = page.screenshot(selector: @selector, format: :png, encoding: :binary)
        page.close
        png
      end

      # Best-effort: let images and webfonts settle before the screenshot.
      def wait_for_assets(page)
        page.network.wait_for_idle(timeout: 12)
      rescue StandardError
        nil
      ensure
        begin
          page.evaluate_async(
            'document.fonts && document.fonts.ready ? document.fonts.ready.then(() => arguments[0]()) : arguments[0]()', 5
          )
        rescue StandardError
          nil
        end
      end

    end
  end
end
