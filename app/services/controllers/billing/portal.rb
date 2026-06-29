# frozen_string_literal: true

module Controllers
  module Billing
    # POST /api/v1/billing/portal
    class Portal < Base
      def call
        require_owner!
        session = Vendors::Stripe::Actions::CreatePortalSession.call(
          workspace: workspace, return_url: "#{SystemConfig.app_host}/assinatura"
        )
        { url: session.url }
      rescue Vendors::Base::NotConfiguredError
        { url: "#{SystemConfig.app_host}/assinatura?portal=mock" }
      end
    end
  end
end
