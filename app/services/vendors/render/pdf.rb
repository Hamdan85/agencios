# frozen_string_literal: true

require 'ferrum'

module Vendors
  # Headless HTML→PDF renderer (Ferrum / Chromium over CDP). Sibling of
  # Render::Html (which screenshots to PNG). Used to render the branded campaign
  # report deck to a PDF that is emailed to the client.
  #
  # The Chromium binary is auto-detected; override with ENV FERRUM_BROWSER_PATH
  # (or CHROME_PATH). In production the runtime image must ship chromium.
  module Render
    class Pdf
      include Launcher

      class RenderError < StandardError; end

      def self.call(...) = new(...).call

      # `html` is a full HTML document (inline CSS; the renderer has no network,
      # so no external stylesheets/fonts/images beyond data: URIs and same-origin
      # ActiveStorage URLs it can reach). Returns binary PDF bytes.
      def initialize(html:, landscape: false)
        @html = html
        @landscape = landscape
      end

      def call
        browser = launch_browser
        begin
          page = browser.create_page
          page.content = @html
          wait_for_assets(page)
          page.pdf(
            format: :A4,
            landscape: @landscape,
            printBackground: true,
            preferCSSPageSize: true,
            encoding: :binary
          )
        ensure
          browser&.quit
        end
      rescue Ferrum::Error, Errno::ENOENT => e
        raise RenderError, "Falha ao gerar PDF (Chromium): #{e.message}"
      end

      private

      # Best-effort: let images and webfonts settle before printing.
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
