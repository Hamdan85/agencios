# frozen_string_literal: true

module Controllers
  module Webhooks
    module Stripe
      # Verifies the Stripe signature and dispatches the event to the subscription
      # sync operation. Raises on an invalid signature (controller → 400).
      class Create < Controllers::Base
        def initialize(payload:, signature:)
          @payload = payload
          @signature = signature
        end

        def call
          event = Vendors::Stripe::Webhook.verify(@payload, @signature)

          # Price/product changes in the Dashboard refresh the cached display
          # amounts (Stripe stays the source of truth for the charged amount).
          return Vendors::Stripe::Actions::SyncPlanPrices.call if event.type.to_s.start_with?('price.', 'product.')

          Operations::Billing::SyncSubscription.call(event)
        end
      end
    end
  end
end
