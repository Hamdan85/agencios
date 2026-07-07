# frozen_string_literal: true

module Vendors
  module Stripe
    # Finds the licensed (plan/seat) item on a retrieved Stripe subscription.
    # Detects the item whose price maps to a plan in the DB catalog (by product →
    # price id → lookup_key, covering both billing intervals); falls back to the
    # sole recurring item (our subscriptions carry exactly one licensed item —
    # metered items were removed in favour of credits).
    module LicensedItem
      module_function

      def find(stripe_sub)
        items = stripe_sub.items&.data || []
        items.find { |it| plan_price?(it.price) } || items.first
      end

      def plan_price?(price)
        return false unless price

        product = price.respond_to?(:product) ? price.product : nil
        product = product.id if product.respond_to?(:id)
        return true if product.present? && PricingPlan.exists?(stripe_product_id: product)

        if price.id.present? &&
           PricingPlan.where('stripe_price_id = :i OR stripe_annual_price_id = :i', i: price.id).exists?
          return true
        end

        lookup = price.respond_to?(:lookup_key) ? price.lookup_key : nil
        lookup.present? &&
          PricingPlan.where('stripe_lookup_key = :l OR stripe_annual_lookup_key = :l', l: lookup).exists?
      end
    end
  end
end
