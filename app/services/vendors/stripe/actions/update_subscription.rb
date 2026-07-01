# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Swap an existing subscription's licensed plan/seat price (a plan change for
      # a workspace that already has a live Stripe subscription). Proration is left
      # to Stripe's default. The resulting `customer.subscription.updated` webhook
      # reconciles the local Subscription row.
      class UpdateSubscription
        def self.call(...) = new(...).call

        def initialize(subscription:, plan:, interval: "month", quantity: nil, client: nil)
          @subscription = subscription # local Subscription record
          @plan         = plan.to_s
          @interval     = %w[month year].include?(interval.to_s) ? interval.to_s : "month"
          @quantity     = quantity
          @client       = client || Client.new
        end

        def call
          stripe_sub = @client.retrieve_subscription(
            @subscription.stripe_subscription_id, expand: ["items.data.price"]
          )
          item = licensed_item(stripe_sub)
          raise Client::Error, "Item de assinatura licenciado não encontrado." unless item

          params = { price: resolve_price_id }
          params[:quantity] = @quantity if @quantity
          @client.update_subscription_item(item["id"] || item.id, params)
        end

        # Interval-aware price resolution (mirrors CreateCheckoutSession).
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

          @client.plan_price_id(@plan)
        end

        private

        # The licensed (plan/seat) item. Detect the item whose price maps to a
        # plan in the DB catalog (by product → price id → lookup_key, covering both
        # billing intervals); fall back to the sole recurring item (our
        # subscriptions carry exactly one licensed item — metered items were
        # removed in favour of credits).
        def licensed_item(stripe_sub)
          items = stripe_sub.items&.data || []
          items.find { |it| plan_price?(it.price) } || items.first
        end

        def plan_price?(price)
          return false unless price

          product = price.respond_to?(:product) ? price.product : nil
          product = product.id if product.respond_to?(:id)
          return true if product.present? && PricingPlan.exists?(stripe_product_id: product)

          if price.id.present? &&
             PricingPlan.where("stripe_price_id = :i OR stripe_annual_price_id = :i", i: price.id).exists?
            return true
          end

          lookup = price.respond_to?(:lookup_key) ? price.lookup_key : nil
          lookup.present? &&
            PricingPlan.where("stripe_lookup_key = :l OR stripe_annual_lookup_key = :l", l: lookup).exists?
        end
      end
    end
  end
end
