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
        # Dev/local without Stripe keys — mock checkout screen. In production a
        # missing Stripe config must surface loudly, not bounce the user back to
        # /assinatura with no explanation.
        raise unless Rails.env.local?

        { url: "#{SystemConfig.app_host}/assinatura?checkout=mock" }
      end
    end
  end
end
