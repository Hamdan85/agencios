# frozen_string_literal: true

module Vendors
  module Posthog
    module Actions
      # Sends a server-side product-analytics event to PostHog.
      #
      #   Vendors::Posthog::Actions::Capture.call(
      #     user:  current_user,                # or distinct_id: "anon-123"
      #     event: "subscription_payment",
      #     properties: { plan: "agencia", amount_cents: 9900 },
      #     groups: { workspace: workspace.id } # optional B2B group analytics
      #   )
      #
      # `distinct_id` defaults to `user.id.to_s`, matching the SPA identify call,
      # so client- and server-side events land on one person. No PII belongs in
      # `properties` unless you accept it going to PostHog only (this is a
      # PostHog-only sink — unlike the client facade, nothing here fans out to
      # GTM or the Meta Pixel).
      #
      # No-ops (returns false) when PostHog is unconfigured. Never raises into the
      # caller — instrumentation must not break a domain operation or a webhook.
      class Capture
        def self.call(event:, user: nil, distinct_id: nil, properties: {}, groups: nil)
          new(event: event, user: user, distinct_id: distinct_id, properties: properties, groups: groups).call
        end

        def initialize(event:, user: nil, distinct_id: nil, properties: {}, groups: nil)
          @event = event
          @distinct_id = (distinct_id || user&.id)&.to_s
          @properties = properties || {}
          @groups = groups
        end

        def call
          client = Vendors::Posthog::Client.instance
          return false unless client && @distinct_id.present?

          attrs = { distinct_id: @distinct_id, event: @event, properties: @properties.compact }
          attrs[:groups] = @groups.compact if @groups.present?
          client.capture(attrs)
          true
        rescue StandardError => e
          Rails.logger.error("[Vendors::Posthog::Actions::Capture] #{e.class}: #{e.message}")
          false
        end
      end
    end
  end
end
