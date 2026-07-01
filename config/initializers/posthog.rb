# frozen_string_literal: true

# PostHog server-side analytics.
#
# Configuration is read from the environment (see Vendors::Posthog::Client):
#   VITE_POSTHOG_PROJECT_TOKEN — project API key (phc_...), shared with the SPA.
#                                POSTHOG_API_KEY is an optional server override.
#   VITE_POSTHOG_HOST          — ingestion host. Falls back to POSTHOG_HOST, then
#                                the US-cloud default.
#
# Capture events via Vendors::Posthog::Actions::Capture. Everything no-ops
# gracefully when unconfigured, and only emits in production (or when
# POSTHOG_ENABLED=true), mirroring the SPA's PROD-only, consent-gated load.
#
# Deferred to after_initialize so the autoloader can resolve Vendors::Posthog.
Rails.application.config.after_initialize do
  if Vendors::Posthog::Client.enabled?
    # Build the client eagerly so its background flush thread is ready, and make
    # sure queued events are flushed on a clean process exit.
    Vendors::Posthog::Client.instance
    at_exit { Vendors::Posthog::Client.shutdown }
  end
end
