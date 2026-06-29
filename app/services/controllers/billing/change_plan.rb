# frozen_string_literal: true

module Controllers
  module Billing
    # POST /api/v1/billing/change_plan
    class ChangePlan < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_owner!
        plan_meta = Plans.find(@params[:plan])
        raise Operations::Errors::Invalid, "Plano inválido." unless plan_meta

        # TODO: Vendors::Stripe::Actions::UpdateSubscription — sync the plan change
        # to Stripe before persisting locally.
        subscription = workspace.subscription
        subscription.update!(plan: plan_meta[:key], seats: plan_meta[:seats], status: "active")
        { subscription: serialize(subscription, SubscriptionSerializer) }
      end
    end
  end
end
