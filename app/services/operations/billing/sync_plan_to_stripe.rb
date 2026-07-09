# frozen_string_literal: true

module Operations
  module Billing
    # Push an admin-edited plan's amounts (monthly + annual) TO Stripe, idempotently.
    #
    # The DB `PricingPlan` is the SOURCE OF TRUTH for price: saving it in /admin
    # syncs Stripe automatically (ActiveAdmin after_save), plus a manual
    # "Sincronizar com o Stripe" button. Called from the admin controller — never
    # from an AR callback (repo rule).
    #
    # Ensures ONE stable Product per plan (a durable identity for grandfathering),
    # then per interval: reuses the current Price when its amount already matches
    # (no-op), else mints a NEW Price carrying the plan's stable lookup_key and
    # archives the old one. Stripe Prices are immutable, so a change is always a new
    # Price; existing subscribers keep their price until individually migrated.
    class SyncPlanToStripe < Operations::Base
      def initialize(plan:, client: nil)
        @plan   = plan
        @client = client || Vendors::Stripe::Client.new
      end

      def call
        ensure_product!
        intervals.each { |spec| ensure_price!(spec) }
        @plan
      end

      private

      def ensure_product!
        if @plan.stripe_product_id.present?
          @client.update_product(@plan.stripe_product_id, name: product_name, active: @plan.active)
        else
          product = @client.create_product(name: product_name, metadata: { plan: @plan.key })
          @plan.update!(stripe_product_id: product.id)
        end
      end

      # Mint a new Price only when the live Stripe amount doesn't already match the
      # plan's edited amount — so a plain save (name/features/active) is a no-op.
      def ensure_price!(spec)
        return if price_current?(spec)

        old_id = @plan.public_send(spec[:id_col])
        price  = @client.create_price(
          product: @plan.stripe_product_id, unit_amount: spec[:amount],
          lookup_key: spec[:lookup_key], interval: spec[:interval]
        )
        @plan.update!(
          spec[:id_col] => price.id,
          spec[:lookup_col] => spec[:lookup_key],
          spec[:cents_col] => spec[:amount]
        )
        archive_old!(old_id, price.id)
      end

      def price_current?(spec)
        price_id = @plan.public_send(spec[:id_col])
        return false if price_id.blank?

        price = @client.retrieve_price(price_id)
        price&.active && price.unit_amount == spec[:amount] &&
          price.recurring&.interval == spec[:interval]
      rescue Vendors::Stripe::Client::Error
        false # missing/deleted price → mint a fresh one
      end

      def archive_old!(old_id, new_id)
        return if old_id.blank? || old_id == new_id

        @client.deactivate_price(old_id)
      rescue Vendors::Stripe::Client::Error => e
        Rails.logger.warn("[SyncPlanToStripe] could not archive price #{old_id}: #{e.message}")
      end

      # The two Prices to keep in sync per plan, and where to cache each id/amount.
      def intervals
        [
          { interval: 'month', lookup_key: @plan.stripe_lookup_key.presence || "#{@plan.key}_monthly",
            amount: @plan.price_cents,
            id_col: :stripe_price_id, cents_col: :price_cents, lookup_col: :stripe_lookup_key },
          { interval: 'year', lookup_key: @plan.stripe_annual_lookup_key.presence || "#{@plan.key}_yearly",
            amount: Pricing.annual_price_cents_for(@plan.key),
            id_col: :stripe_annual_price_id, cents_col: :annual_price_cents, lookup_col: :stripe_annual_lookup_key }
        ]
      end

      def product_name = "agencios — #{@plan.name}"
    end
  end
end
