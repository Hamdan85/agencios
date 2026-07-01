# frozen_string_literal: true

module Vendors
  module Stripe
    # Platform-level Stripe client for agencios SaaS billing (the workspace's own
    # subscription: one licensed seat item + two metered usage items via Billing
    # Meters). This is a thin wrapper over the official `stripe` gem (19.x) — the
    # gem owns HTTP, retries and idempotency, so we do NOT use Vendors::Base's
    # Faraday plumbing here. We DO inherit from Vendors::Base for `credential` /
    # `require_credential!` and the shared error hierarchy.
    #
    # The secret key is read once per client from credentials (ENV fallback for
    # local dev) and pinned to a stable API version so webhook payload shapes
    # don't drift. Price ids are resolved from credentials too, so they are never
    # hard-coded.
    #
    # See docs/integrations/stripe-billing.md.
    #
    # ── Expected Rails credentials (rails credentials:edit) ──────────────────
    #
    #   stripe:
    #     secret_key: sk_live_...            # ENV fallback: STRIPE_SECRET_KEY
    #     webhook_secret: whsec_...          # ENV fallback: STRIPE_WEBHOOK_SECRET
    #     prices:
    #       solo: price_...                  # Solo licensed price (qty 1)
    #       agencia: price_...               # Agência per-seat licensed price (qty 5–20)
    #       enterprise: price_...            # Enterprise per-seat licensed price (qty 20+)
    #       carousel_generation: price_...   # metered price tied to carousel meter
    #       video_generation: price_...      # metered price tied to video meter
    #
    # Both `secret_key` and `webhook_secret` also accept ENV fallbacks
    # (STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET) for local dev — see
    # Vendors::Base#credential.
    class Client < Vendors::Base
      # Pin the API version so webhook payload shapes are stable across gem
      # upgrades. Billing Meters + the metered-billing webhooks require Basil
      # (2025-03-31) or later. Overridable via the stripe.api_version credential.
      DEFAULT_API_VERSION = "2025-03-31.basil"

      # Stripe price ids are resolved per plan from credentials by these keys.
      PLAN_PRICE_KEYS = {
        "solo" => :solo,
        "agencia" => :agencia,
        "enterprise" => :enterprise
      }.freeze

      # Metered usage prices that ride on every subscription, by Generation kind.
      METERED_PRICE_KEYS = {
        carousel: :carousel_generation,
        video: :video_generation
      }.freeze

      def initialize
        configure!
      end

      # ── Subscriptions / Checkout / Portal ─────────────────────────────────

      def create_checkout_session(params)
        with_error_mapping { ::Stripe::Checkout::Session.create(params) }
      end

      def create_portal_session(params)
        with_error_mapping { ::Stripe::BillingPortal::Session.create(params) }
      end

      # ── Customers ─────────────────────────────────────────────────────────

      def create_customer(name:, email: nil, metadata: {})
        with_error_mapping do
          ::Stripe::Customer.create({ name: name, email: email, metadata: metadata }.compact)
        end
      end

      # ── Provisioning (create Products + Prices) ───────────────────────────

      def create_product(name:, metadata: {})
        with_error_mapping { ::Stripe::Product.create(name: name, metadata: metadata) }
      end

      # Archive a Price (Prices are immutable — a price change creates a new one
      # and deactivates the old so it drops out of the Dashboard/checkout).
      def deactivate_price(price_id)
        with_error_mapping { ::Stripe::Price.update(price_id, { active: false }) }
      end

      # A recurring monthly Price tagged with a stable `lookup_key`.
      # `transfer_lookup_key: true` moves the key off any existing Price so
      # re-provisioning after a price change points the key at the new amount.
      def create_price(product:, unit_amount:, lookup_key:, currency: "brl", interval: "month")
        with_error_mapping do
          ::Stripe::Price.create(
            product: product,
            currency: currency,
            unit_amount: unit_amount,
            recurring: { interval: interval },
            lookup_key: lookup_key,
            transfer_lookup_key: true
          )
        end
      end

      def retrieve_subscription(subscription_id, params = {})
        with_error_mapping { ::Stripe::Subscription.retrieve({ id: subscription_id }.merge(params)) }
      end

      # Resolve the current active Price for a stable `lookup_key`. This is how we
      # avoid hard-coding price ids: tag each plan Price with a lookup_key in the
      # Dashboard, and a price change (new Price with the key transferred) flows
      # through here with no deploy. Returns the Stripe::Price (nil if none).
      def price_by_lookup_key(lookup_key)
        with_error_mapping do
          ::Stripe::Price.list(lookup_keys: [lookup_key], active: true, expand: ["data.product"]).data.first
        end
      end

      def update_subscription_item(item_id, params)
        with_error_mapping { ::Stripe::SubscriptionItem.update(item_id, params) }
      end

      # ── Billing Meters ────────────────────────────────────────────────────

      # POST /v1/billing/meter_events — record one usage event. `value` is sent as
      # a string (Stripe stores the payload values as strings). `identifier` is the
      # dedup key; Stripe enforces uniqueness for ~24h+, so a retried job is safe.
      def create_meter_event(event_name:, stripe_customer_id:, value:, identifier:, timestamp: nil)
        params = {
          event_name: event_name,
          payload: { stripe_customer_id: stripe_customer_id, value: value.to_s },
          identifier: identifier,
          timestamp: timestamp
        }.compact

        with_error_mapping { ::Stripe::Billing::MeterEvent.create(params) }
      end

      # POST /v1/billing/meters — provisioning helper (run once per environment to
      # create the two meters). Not on the hot path; here for completeness/setup.
      def create_meter(display_name:, event_name:, formula: "sum", payload_key: "value")
        params = {
          display_name: display_name,
          event_name: event_name,
          default_aggregation: { formula: formula },
          value_settings: { event_payload_key: payload_key },
          customer_mapping: { type: "by_id", event_payload_key: "stripe_customer_id" }
        }

        with_error_mapping { ::Stripe::Billing::Meter.create(params) }
      end

      # GET /v1/billing/meters/{id}/event_summaries — aggregated usage for a
      # customer over a window (in-app usage dashboards / free-tier remaining).
      def list_event_summaries(meter_id, customer:, start_time:, end_time:)
        with_error_mapping do
          ::Stripe::Billing::Meter.list_event_summaries(
            meter_id,
            customer: customer,
            start_time: start_time,
            end_time: end_time
          )
        end
      end

      # ── Credential resolution ─────────────────────────────────────────────

      def api_version
        credential(:stripe, :api_version) || DEFAULT_API_VERSION
      end

      def secret_key
        require_credential!(
          credential(:stripe, :secret_key, env: "STRIPE_SECRET_KEY"),
          "stripe.secret_key"
        )
      end

      # Resolve the licensed seat/plan price id for a plan key (solo/agencia/enterprise).
      def plan_price_id(plan)
        key = PLAN_PRICE_KEYS.fetch(plan.to_s) do
          raise Error, "Plano Stripe desconhecido: #{plan.inspect}"
        end
        require_credential!(credential(:stripe, :prices, key), "stripe.prices.#{key}")
      end

      # The two metered usage price ids, in a stable order, that ride on every
      # subscription alongside the licensed plan item.
      def metered_price_ids
        METERED_PRICE_KEYS.values.map do |key|
          require_credential!(credential(:stripe, :prices, key), "stripe.prices.#{key}")
        end
      end

      private

      # Set the process-wide Stripe config from credentials. Idempotent — safe to
      # call per client. `Stripe.api_key=` is global to the gem.
      def configure!
        ::Stripe.api_key = secret_key
        ::Stripe.api_version = api_version
      end

      # Map the stripe gem's exception hierarchy onto Vendors::Base's errors so
      # callers handle billing failures uniformly with the other vendors.
      def with_error_mapping
        yield
      rescue ::Stripe::AuthenticationError, ::Stripe::PermissionError => e
        raise AuthenticationError.new(e.message, status: e.respond_to?(:http_status) ? e.http_status : nil)
      rescue ::Stripe::RateLimitError => e
        raise RateLimitError.new(e.message, status: e.respond_to?(:http_status) ? e.http_status : nil)
      rescue ::Stripe::APIConnectionError, ::Stripe::APIError => e
        raise ServerError.new(e.message, status: e.respond_to?(:http_status) ? e.http_status : nil)
      rescue ::Stripe::StripeError => e
        raise Error.new(e.message, status: e.respond_to?(:http_status) ? e.http_status : nil)
      end
    end
  end
end
