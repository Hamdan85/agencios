# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Create a subscription Checkout Session for a workspace's SaaS plan.
      #
      # The session has ONE licensed plan/seat price WITH `quantity`. Video/image
      # usage is billed via the prepaid credit wallet (one-time payments), NOT
      # Stripe usage meters, so no metered line items ride on the subscription.
      #
      # The trial is CARD-REQUIRED: `payment_method_collection: "always"` forces a
      # card at Checkout even during the trial, and the trial cancels if the card
      # ever goes missing. Trial length is configurable (Pricing.trial_days).
      #
      # See docs/integrations/stripe-billing.md §3.
      class CreateCheckoutSession
        def self.call(...) = new(...).call

        # `interval` is "month" (default) or "year" (annual, discounted).
        def initialize(workspace:, plan:, success_url:, cancel_url:, interval: "month", client: nil)
          @workspace = workspace
          @plan = plan.to_s
          @interval = %w[month year].include?(interval.to_s) ? interval.to_s : "month"
          @success_url = success_url
          @cancel_url = cancel_url
          @client = client || Client.new
        end

        # Returns the Stripe::Checkout::Session (its `.url` is the redirect target).
        def call
          @client.create_checkout_session(
            mode: "subscription",
            line_items: [licensed_line_item],
            customer: existing_customer_id,
            client_reference_id: @workspace.id.to_s,
            # Force a card up front, even for the trial (card-required trial).
            payment_method_collection: "always",
            success_url: @success_url,
            cancel_url: @cancel_url,
            subscription_data: subscription_data,
            metadata: { workspace_id: @workspace.id.to_s, plan: @plan }
          )
        end

        private

        def subscription_data
          data = { metadata: { workspace_id: @workspace.id.to_s, plan: @plan } }
          # Trial ONLY on the first purchase — not on re-subscribe / plan change.
          if Pricing.trial_days.positive? && trial_eligible?
            data[:trial_period_days] = Pricing.trial_days
            # If the trial ends with no usable card, cancel rather than silently
            # granting free access.
            data[:trial_settings] = { end_behavior: { missing_payment_method: "cancel" } }
          end
          data
        end

        def trial_eligible?
          !@workspace.subscription&.trial_used?
        end

        # The licensed plan line. Plans are FLAT (quantity 1) — the advertised
        # price is per-workspace, and seat/client limits are enforced app-side
        # (Pricing.seat_limit_for / Workspace#seat_limit), not via Stripe quantity.
        def licensed_line_item
          { price: resolve_price_id, quantity: 1 }
        end

        # Resolve the Stripe Price id for the plan + interval, preferring the DB
        # catalog's cached Stripe pointers (price id → live lookup_key) and falling
        # back to the legacy monthly credential id so nothing breaks pre-migration.
        def resolve_price_id
          plan = PricingPlan.find_by(key: @plan)
          if plan
            cached = @interval == "year" ? plan.stripe_annual_price_id : plan.stripe_price_id
            return cached if cached.present?

            lookup = @interval == "year" ? plan.stripe_annual_lookup_key : plan.stripe_lookup_key
            if lookup.present?
              price = @client.price_by_lookup_key(lookup)
              return price.id if price
            end
          end

          @client.plan_price_id(@plan) # legacy monthly-only fallback
        end

        # Ensure a single Stripe Customer per workspace (stamped with workspace_id
        # metadata) so the subscription and credit-pack purchases share it.
        def existing_customer_id
          EnsureCustomer.call(workspace: @workspace, client: @client)
        end
      end
    end
  end
end
