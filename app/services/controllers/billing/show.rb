# frozen_string_literal: true

module Controllers
  module Billing
    class Show < Base
      def call
        {
          subscription: serialize(workspace.subscription, SubscriptionSerializer),
          plans: Plans.all,
          annual_discount_percent: Pricing.annual_discount_percent,
          credits: Pricing.public_catalog.slice(:credit_unit_cents, :credit_packs, :credit_costs)
        }
      end
    end
  end
end
