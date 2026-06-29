# frozen_string_literal: true

module Controllers
  module Billing
    # POST /api/v1/billing/cancel
    class Cancel < Base
      def call
        require_owner!
        subscription = workspace.subscription
        subscription.update!(cancel_at: 30.days.from_now)
        { subscription: serialize(subscription, SubscriptionSerializer) }
      end
    end
  end
end
