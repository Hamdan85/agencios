# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Create a Billing Portal session so a workspace owner can self-serve:
      # update the payment method, view invoices, change plan/seats, and cancel.
      #
      # POST /v1/billing_portal/sessions — requires the workspace's Stripe
      # `customer`. The returned session `.url` is a one-time redirect target.
      #
      # See docs/integrations/stripe-billing.md §5.
      class CreatePortalSession
        def self.call(...) = new(...).call

        def initialize(workspace:, return_url:, client: nil)
          @workspace = workspace
          @return_url = return_url
          @client = client || Client.new
        end

        # Returns the Stripe::BillingPortal::Session (its `.url` is the redirect).
        def call
          @client.create_portal_session(
            customer: customer_id,
            return_url: @return_url
          )
        end

        private

        def customer_id
          id = @workspace.subscription&.stripe_customer_id
          return id if id.present?

          raise Vendors::Base::Error,
                "Workspace #{@workspace.id} não possui stripe_customer_id; finalize o checkout antes do portal."
        end
      end
    end
  end
end
