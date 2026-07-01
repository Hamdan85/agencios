# frozen_string_literal: true

module Api
  module V1
    # Public pricing catalog for the marketing landing page + signup (plans,
    # credit packs, per-action credit costs, trial length). No auth, no tenant.
    class PricingController < BaseController
      allow_unauthenticated_access
      skip_billing_gate

      def show = render_ok(Pricing.public_catalog)
    end
  end
end
