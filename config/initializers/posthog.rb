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
    # Quiet the SDK's own INFO chatter (e.g. "No personal API key provided,
    # disabling local evaluation" — expected: we only CAPTURE events, we don't
    # do server-side feature-flag local evaluation, which is the only thing a
    # personal API key unlocks). Real send failures still surface via the
    # client's `on_error` → Rails.logger.error.
    PostHog::Logging.logger = Logger.new($stdout).tap { |l| l.level = Logger::WARN }

    # Build the client eagerly so its background flush thread is ready, and make
    # sure queued events are flushed on a clean process exit.
    Vendors::Posthog::Client.instance
    at_exit { Vendors::Posthog::Client.shutdown }
  end
end
