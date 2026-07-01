# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Ensure the workspace has a Stripe Customer, returning its id. Idempotent:
      # returns the stored id if present, else creates a Customer (stamped with
      # `workspace_id` metadata so webhooks can resolve the tenant) and caches it
      # on the workspace's Subscription.
      #
      # Used by the checkout flows (so the subscription + credit-pack purchases
      # share one Customer) and the `pricing:stripe:backfill_customers` rake task.
      class EnsureCustomer
        def self.call(...) = new(...).call

        def initialize(workspace:, client: nil)
          @workspace = workspace
          @client    = client || Client.new
        end

        def call
          subscription = @workspace.subscription ||
                         @workspace.build_subscription(plan: :solo, seats: 1, status: 'incomplete')
          return subscription.stripe_customer_id if subscription.stripe_customer_id.present?

          customer = @client.create_customer(
            name: @workspace.name,
            email: @workspace.owner&.email,
            metadata: { workspace_id: @workspace.id.to_s }
          )
          subscription.update!(stripe_customer_id: customer.id)
          customer.id
        end
      end
    end
  end
end
