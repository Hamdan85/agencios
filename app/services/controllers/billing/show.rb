# frozen_string_literal: true

module Controllers
  module Billing
    class Show < Base
      def call
        {
          subscription: serialize(workspace.subscription, SubscriptionSerializer),
          plans: Plans::ALL
        }
      end
    end
  end
end
