# frozen_string_literal: true

module Vendors
  module Posthog
    # Thin wrapper around the posthog-ruby SDK. Holds a single memoized
    # PostHog::Client (it owns a background flush thread, so we never build more
    # than one per process). Returns nil — and every action no-ops — when the
    # integration is unconfigured, so server-side analytics stays inert until the
    # project token is set, mirroring the SPA's env-gated behaviour.
    #
    # The distinct_id we send is the user's id as a string, matching the SPA's
    # `analytics.identify(user.id, ...)` call (see AnalyticsBridge.jsx), so a
    # person is a SINGLE PostHog profile across client- and server-side events —
    # no duplicate paths from mismatched ids.
    class Client
      # us.i.posthog.com is the US-cloud ingestion host (same region as the SPA).
      DEFAULT_HOST = 'https://us.i.posthog.com'

      class << self
        def instance
          return @instance if defined?(@instance)

          @instance = build
        end

        def configured?
          api_key.present?
        end

        # Only emit in production, mirroring the SPA's consent-gated PROD-only
        # load, so local and test runs never pollute PostHog. Set
        # POSTHOG_ENABLED=true to opt a non-production environment in (e.g. staging).
        def enabled?
          configured? && (Rails.env.production? || ENV['POSTHOG_ENABLED'] == 'true')
        end

        def shutdown
          @instance&.shutdown if defined?(@instance)
        end

        def reset!
          remove_instance_variable(:@instance) if defined?(@instance)
        end

        private

        def build
          return nil unless enabled?

          ::PostHog::Client.new(
            api_key: api_key,
            host: host,
            on_error: ->(status, msg) { Rails.logger.error("[Vendors::Posthog] #{status}: #{msg}") }
          )
        end

        # The project API key (phc_...). VITE_POSTHOG_PROJECT_TOKEN is the value
        # the SPA already reads, so one env var powers both the browser and the
        # server; POSTHOG_API_KEY is an optional server-only override.
        def api_key
          ENV['POSTHOG_API_KEY'].presence || ENV['VITE_POSTHOG_PROJECT_TOKEN'].presence
        end

        def host
          ENV['POSTHOG_HOST'].presence || ENV['VITE_POSTHOG_HOST'].presence || DEFAULT_HOST
        end
      end
    end
  end
end
