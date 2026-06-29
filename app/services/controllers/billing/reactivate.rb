# frozen_string_literal: true

module Controllers
  module Billing
    # POST /api/v1/billing/reactivate
    class Reactivate < Base
      def call
        require_owner!
        subscription = workspace.subscription
        subscription.update!(cancel_at: nil)
        { subscription: serialize(subscription, SubscriptionSerializer) }
      end
    end
  end
end
