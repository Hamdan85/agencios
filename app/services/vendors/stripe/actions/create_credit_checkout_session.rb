# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # One-time Checkout Session to buy a prepaid credit pack. Uses inline
      # `price_data` (BRL) so pack sizes/prices stay config-driven (Pricing) with
      # no pre-created Stripe prices. The purchased credits are applied when the
      # `checkout.session.completed` webhook fires (mode = "payment").
      class CreateCreditCheckoutSession
        def self.call(...) = new(...).call

        def initialize(workspace:, pack:, success_url:, cancel_url:, client: nil)
          @workspace   = workspace
          @pack        = pack # a Pricing::CREDIT_PACKS entry
          @success_url = success_url
          @cancel_url  = cancel_url
          @client      = client || Client.new
        end

        def call
          @client.create_checkout_session(
            mode: 'payment',
            customer: existing_customer_id,
            client_reference_id: @workspace.id.to_s,
            success_url: @success_url,
            cancel_url: @cancel_url,
            line_items: [{
              quantity: 1,
              price_data: {
                currency: 'brl',
                unit_amount: @pack[:price_cents],
                product_data: { name: "Créditos agencios — pacote #{@pack[:name]} (#{@pack[:credits]} créditos)" }
              }
            }],
            payment_intent_data: {
              metadata: purchase_metadata
            },
            metadata: purchase_metadata
          )
        end

        private

        def purchase_metadata
          {
            workspace_id: @workspace.id.to_s,
            purpose: 'credit_pack',
            pack: @pack[:key].to_s,
            credits: @pack[:credits].to_s
          }
        end

        # Attach the purchase to the workspace's single Stripe Customer (created if
        # missing) so the credits land on the same customer as the subscription.
        def existing_customer_id
          EnsureCustomer.call(workspace: @workspace, client: @client)
        end
      end
    end
  end
end
