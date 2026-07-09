# frozen_string_literal: true

require 'ferrum'

module Vendors
  module Render
    # Shared Chromium/Ferrum launch logic for the HTML→PNG and HTML→PDF renderers.
    #
    # Browser *startup* (the CDP websocket handshake) is the fragile part under
    # load. When several Sidekiq jobs cold-start Chromium at the same instant on a
    # small box — e.g. a project-wide autopilot GO fans out one run per ticket and
    # each renders a carousel — the handshake can exceed `process_timeout`, raising
    # `Ferrum::ProcessTimeoutError` ("browser did not produce web-socket url within
    # N seconds"). That surfaces as a RenderError and halts the autopilot run.
    #
    # Two defenses, both here so both renderers share them:
    #   * a process-wide mutex serializes cold starts (no thundering herd), so at
    #     most one Chromium boots at a time within a Sidekiq process;
    #   * a transient startup failure is retried a few times with backoff before
    #     giving up — by then the contending launch has finished and freed CPU/RAM.
    module Launcher
      # Only the launch is serialized, not the whole render — pages still render in
      # parallel once their browser is up.
      LAUNCH_MUTEX = Mutex.new

      PROCESS_TIMEOUT     = Integer(ENV.fetch('FERRUM_PROCESS_TIMEOUT', 90))
      OPERATION_TIMEOUT   = Integer(ENV.fetch('FERRUM_TIMEOUT', 60))
      MAX_LAUNCH_ATTEMPTS = 3

      # Launch options common to both renderers. The extra hardening flags keep the
      # cold start lean (no GPU rasterizer, extensions, first-run, or audio stack).
      BASE_BROWSER_OPTIONS = {
        'no-sandbox' => nil,
        'disable-dev-shm-usage' => nil,
        'disable-gpu' => nil,
        'disable-software-rasterizer' => nil,
        'disable-extensions' => nil,
        'no-first-run' => nil,
        'mute-audio' => nil
      }.freeze

      # Boot a Ferrum browser, serialized and retried. Extra Ferrum options (e.g.
      # `window_size`) and browser flags are merged over the defaults.
      def launch_browser(browser_options: {}, **ferrum_options)
        attempts = 0
        begin
          attempts += 1
          LAUNCH_MUTEX.synchronize { build_ferrum(browser_options, ferrum_options) }
        rescue Ferrum::ProcessTimeoutError, Ferrum::DeadBrowserError => e
          raise if attempts >= MAX_LAUNCH_ATTEMPTS

          Rails.logger.warn(
            "[Render::Launcher] Chromium startup failed (attempt #{attempts}/#{MAX_LAUNCH_ATTEMPTS}): #{e.message}"
          )
          sleep(attempts * 2)
          retry
        end
      end

      private

      def build_ferrum(browser_options, ferrum_options)
        Ferrum::Browser.new(
          headless: true,
          browser_path: chromium_path,
          timeout: OPERATION_TIMEOUT,
          process_timeout: PROCESS_TIMEOUT,
          pending_connection_errors: false,
          browser_options: BASE_BROWSER_OPTIONS.merge(browser_options),
          **ferrum_options
        )
      end

      def chromium_path
        ENV['FERRUM_BROWSER_PATH'].presence ||
          ENV['CHROME_PATH'].presence ||
          %w[/usr/bin/chromium /usr/bin/chromium-browser /usr/bin/google-chrome].find { |p| File.executable?(p) }
      end
    end
  end
end
