# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Create a subscription Checkout Session for a workspace's SaaS plan.
      #
      # The session's line items are: ONE licensed plan/seat price WITH `quantity`,
      # plus the TWO metered usage prices WITHOUT `quantity` (Stripe forbids
      # `quantity` on `usage_type=metered` lines). For Agência the seat band is
      # 5–20, exposed as adjustable quantity in Checkout so the customer can pick
      # their seat count; Solo is a flat single-seat plan, Enterprise opens at 20.
      #
      # All three items roll into one subscription / one invoice per period.
      #
      # See docs/integrations/stripe-billing.md §3.
      class CreateCheckoutSession
        def self.call(...) = new(...).call

        # Adjustable seat bands per plan (min/max). nil ⇒ fixed quantity (no
        # adjustable_quantity block emitted).
        SEAT_BANDS = {
          "solo" => nil,
          "agencia" => { minimum: 5, maximum: 20 },
          "enterprise" => { minimum: 20, maximum: 999 }
        }.freeze

        DEFAULT_QUANTITY = { "solo" => 1, "agencia" => 5, "enterprise" => 20 }.freeze

        TRIAL_PERIOD_DAYS = 14

        def initialize(workspace:, plan:, success_url:, cancel_url:, client: nil)
          @workspace = workspace
          @plan = plan.to_s
          @success_url = success_url
          @cancel_url = cancel_url
          @client = client || Client.new
        end

        # Returns the Stripe::Checkout::Session (its `.url` is the redirect target).
        def call
          @client.create_checkout_session(
            mode: "subscription",
            line_items: line_items,
            customer: existing_customer_id,
            client_reference_id: @workspace.id.to_s,
            success_url: @success_url,
            cancel_url: @cancel_url,
            subscription_data: {
              trial_period_days: TRIAL_PERIOD_DAYS,
              metadata: { workspace_id: @workspace.id.to_s, plan: @plan }
            },
            metadata: { workspace_id: @workspace.id.to_s, plan: @plan }
          )
        end

        private

        def line_items
          [licensed_line_item] + metered_line_items
        end

        # The licensed plan/seat line — the only line that carries `quantity`.
        def licensed_line_item
          item = {
            price: @client.plan_price_id(@plan),
            quantity: default_quantity
          }
          band = SEAT_BANDS.fetch(@plan, nil)
          item[:adjustable_quantity] = { enabled: true }.merge(band) if band
          item
        end

        # The two metered usage prices — NEVER carry `quantity`.
        def metered_line_items
          @client.metered_price_ids.map { |price_id| { price: price_id } }
        end

        def default_quantity
          seats = @workspace.seat_count
          floor = DEFAULT_QUANTITY.fetch(@plan, 1)
          [seats, floor].max
        end

        # Reuse the customer if the workspace already has one (so seats/usage stay
        # on a single Stripe customer); nil lets Checkout create one.
        def existing_customer_id
          @workspace.subscription&.stripe_customer_id.presence
        end
      end
    end
  end
end
