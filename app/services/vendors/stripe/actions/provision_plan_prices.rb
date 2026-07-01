# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Idempotently create the Stripe Product + recurring Prices (monthly AND
      # yearly) for each plan in the DB catalog, caching the ids/amounts back onto
      # the PricingPlan rows. Safe to re-run: an existing Price for a lookup_key is
      # reused (no duplicate), only caching ids/amount back.
      #
      # Both prices share the plan's single Product (stable identity for
      # grandfathering). Used by `rake pricing:stripe:provision`.
      class ProvisionPlanPrices
        def self.call(...) = new(...).call

        def initialize(client: nil)
          @client = client || Client.new
        end

        # Returns [{key:, interval:, action:, price_id:, amount_cents:}, ...]
        def call
          PricingPlan.ordered.flat_map { |plan| provision_plan(plan) }
        end

        private

        def provision_plan(plan)
          product = nil # created lazily on the first interval that needs it
          intervals(plan).map do |spec|
            existing = @client.price_by_lookup_key(spec[:lookup_key])
            if existing
              cache!(plan, spec, existing)
              next result(plan, spec, :reused, existing)
            end

            product ||= product_id(ensure_product(plan))
            price = @client.create_price(
              product: product, unit_amount: spec[:amount], lookup_key: spec[:lookup_key], interval: spec[:interval]
            )
            plan.update!(stripe_product_id: plan.stripe_product_id.presence || product)
            cache!(plan, spec, price)
            result(plan, spec, :created, price)
          end
        end

        # The two prices to ensure per plan, with where to cache each.
        def intervals(plan)
          [
            { interval: 'month', lookup_key: plan.stripe_lookup_key.presence || "#{plan.key}_monthly",
              amount: plan.price_cents, id_col: :stripe_price_id, cents_col: :price_cents, lookup_col: :stripe_lookup_key },
            { interval: 'year', lookup_key: plan.stripe_annual_lookup_key.presence || "#{plan.key}_yearly",
              amount: Pricing.annual_price_cents_for(plan.key),
              id_col: :stripe_annual_price_id, cents_col: :annual_price_cents, lookup_col: :stripe_annual_lookup_key }
          ]
        end

        def ensure_product(plan)
          return plan.stripe_product_id if plan.stripe_product_id.present?

          @client.create_product(name: "agencios — #{plan.name}", metadata: { plan: plan.key })
        end

        def cache!(plan, spec, price)
          plan.update!(
            spec[:lookup_col] => spec[:lookup_key],
            spec[:id_col] => price.id,
            spec[:cents_col] => price.unit_amount || spec[:amount],
            stripe_product_id: price_product_id(price) || plan.stripe_product_id
          )
        end

        def product_id(product) = product.respond_to?(:id) ? product.id : product

        def price_product_id(price)
          product = price.respond_to?(:product) ? price.product : nil
          product.respond_to?(:id) ? product.id : product
        end

        def result(plan, spec, action, price)
          { key: plan.key, interval: spec[:interval], action: action,
            price_id: price.id, amount_cents: price.unit_amount || spec[:amount] }
        end
      end
    end
  end
end
