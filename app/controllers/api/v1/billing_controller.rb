# frozen_string_literal: true

module Api
  module V1
    class BillingController < BaseController
      # The whole point of the paywall is to route the user here to pay.
      skip_billing_gate

      def show = render_ok(Controllers::Billing::Show.call)

      # POST /api/v1/billing/checkout_session
      def checkout_session = render_ok(Controllers::Billing::CheckoutSession.call(params:))

      # POST /api/v1/billing/portal
      def portal = render_ok(Controllers::Billing::Portal.call)

      # POST /api/v1/billing/change_plan
      def change_plan = render_ok(Controllers::Billing::ChangePlan.call(params:))

      # POST /api/v1/billing/cancel
      def cancel = render_ok(Controllers::Billing::Cancel.call)

      # POST /api/v1/billing/reactivate
      def reactivate = render_ok(Controllers::Billing::Reactivate.call)
    end
  end
end
