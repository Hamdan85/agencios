# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Pull the current Stripe amount for each plan (by lookup_key) into the DB
      # catalog, so the landing page + in-app display always match what Stripe
      # actually charges. Stripe is the source of truth for the amount; this just
      # caches it. Triggered by the `price.*`/`product.*` webhooks and the admin
      # "Sincronizar preços do Stripe" action.
      #
      # Returns the number of plans updated.
      class SyncPlanPrices
        def self.call(...) = new(...).call

        def initialize(client: nil)
          @client = client || Client.new
        end

        def call
          updated = 0
          PricingPlan.find_each do |plan|
            updated += 1 if sync_monthly(plan)
            updated += 1 if sync_annual(plan)
          end
          updated
        rescue Vendors::Base::NotConfiguredError, Client::Error => e
          Rails.logger.warn("[SyncPlanPrices] skipped: #{e.message}")
          updated
        end

        private

        def sync_monthly(plan)
          return false if plan.stripe_lookup_key.blank?

          price = @client.price_by_lookup_key(plan.stripe_lookup_key)
          return false unless price

          plan.update!(
            stripe_price_id: price.id,
            stripe_product_id: product_id(price) || plan.stripe_product_id,
            price_cents: price.unit_amount || plan.price_cents
          )
          true
        end

        def sync_annual(plan)
          return false if plan.stripe_annual_lookup_key.blank?

          price = @client.price_by_lookup_key(plan.stripe_annual_lookup_key)
          return false unless price

          plan.update!(
            stripe_annual_price_id: price.id,
            stripe_product_id: product_id(price) || plan.stripe_product_id,
            annual_price_cents: price.unit_amount || plan.annual_price_cents
          )
          true
        end

        # `product` is a string id, or the expanded object when we requested it.
        def product_id(price)
          product = price.respond_to?(:product) ? price.product : nil
          product.respond_to?(:id) ? product.id : product
        end
      end
    end
  end
end
