# frozen_string_literal: true

module Controllers
  module Billing
    # The SaaS plan catalog surfaced on the workspace's own subscription screen.
    # Thin adapter over the single pricing source of truth (`Pricing`). Resolved
    # lazily (never at load time) so admin edits reflect immediately.
    module Plans
      module_function

      def all
        Pricing.plans.map do |p|
          annual = Pricing.annual_price_cents_for(p[:key])
          p.slice(:key, :name, :price_cents, :seats, :features)
           .merge(
             name: Pricing.localize_name(p[:key], p[:name]),
             features: Pricing.localize_features(p[:features]),
             included_credits: p[:included_credits],
             annual_price_cents: annual,
             annual_monthly_equivalent_cents: (annual / 12.0).round
           )
        end
      end

      def find(key)
        all.find { |plan| plan[:key] == key.to_s }
      end
    end
  end
end
