# frozen_string_literal: true

module Controllers
  module Billing
    # POST /api/v1/billing/checkout_session
    class CheckoutSession < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_owner!
        session = Vendors::Stripe::Actions::CreateCheckoutSession.call(
          workspace: workspace,
          plan: @params[:plan].presence || workspace.plan.to_s,
          interval: @params[:interval].presence || 'month',
          success_url: "#{SystemConfig.app_host}/assinatura?checkout=success",
          cancel_url: "#{SystemConfig.app_host}/assinatura?checkout=cancelled"
        )
        { url: session.url }
      rescue Vendors::Base::NotConfiguredError
        { url: "#{SystemConfig.app_host}/assinatura?checkout=mock" }
      end
    end
  end
end
