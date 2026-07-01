# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Push a plan's DB amounts (monthly + annual) TO Stripe: create a NEW Price
      # for each interval carrying the plan's stable `lookup_key`
      # (transfer_lookup_key moves the key onto the new Price), cache the new ids
      # back, and archive the superseded Prices.
      #
      # This is the admin-driven "publish" path — it makes an ActiveAdmin price
      # edit take effect in Stripe. Note: like all Stripe price changes, it affects
      # NEW checkouts; existing subscribers keep their current price (grandfathered)
      # until individually migrated.
      #
      # Contrast with ProvisionPlanPrices (reuses an existing Price for the
      # lookup_key — for first-time bootstrap) and SyncPlanPrices (pulls FROM
      # Stripe). Publish always CREATES (the amount changed).
      class PublishPlanPrices
        def self.call(...) = new(...).call

        def initialize(plan: nil, client: nil)
          @plan   = plan
          @client = client || Client.new
        end

        # Returns [{key:, prices: [{interval:, price_id:, amount_cents:}, ...]}, ...]
        def call
          plans = @plan ? [@plan] : PricingPlan.ordered.to_a
          plans.map { |plan| publish(plan) }
        end

        private

        def publish(plan)
          product = product_id(ensure_product(plan))
          plan.update!(stripe_product_id: plan.stripe_product_id.presence || product)

          prices = intervals(plan).map do |spec|
            old_id = plan.public_send(spec[:id_col])
            price = @client.create_price(
              product: product, unit_amount: spec[:amount], lookup_key: spec[:lookup_key], interval: spec[:interval]
            )
            plan.update!(
              spec[:id_col]     => price.id,
              spec[:lookup_col] => spec[:lookup_key],
              spec[:cents_col]  => spec[:amount]
            )
            archive_old(old_id, price.id)
            { interval: spec[:interval], price_id: price.id, amount_cents: spec[:amount] }
          end

          { key: plan.key, prices: prices }
        end

        def intervals(plan)
          [
            { interval: "month", lookup_key: plan.stripe_lookup_key.presence || "#{plan.key}_monthly",
              amount: plan.price_cents, id_col: :stripe_price_id, cents_col: :price_cents, lookup_col: :stripe_lookup_key },
            { interval: "year", lookup_key: plan.stripe_annual_lookup_key.presence || "#{plan.key}_yearly",
              amount: Pricing.annual_price_cents_for(plan.key),
              id_col: :stripe_annual_price_id, cents_col: :annual_price_cents, lookup_col: :stripe_annual_lookup_key }
          ]
        end

        def ensure_product(plan)
          return plan.stripe_product_id if plan.stripe_product_id.present?

          @client.create_product(name: "agencios — #{plan.name}", metadata: { plan: plan.key })
        end

        def archive_old(old_id, new_id)
          return if old_id.blank? || old_id == new_id

          @client.deactivate_price(old_id)
        rescue Client::Error => e
          Rails.logger.warn("[PublishPlanPrices] could not archive price #{old_id}: #{e.message}")
        end

        def product_id(product) = product.respond_to?(:id) ? product.id : product
      end
    end
  end
end
