# frozen_string_literal: true

module Vendors
  module Stripe
    # Verifies inbound Stripe webhook deliveries. Stripe signs the raw request
    # body with a per-endpoint signing secret and sends it in the `Stripe-Signature`
    # header; `Stripe::Webhook.construct_event` checks the HMAC-SHA256 signature and
    # the timestamp tolerance, returning a parsed `Stripe::Event` or raising on a
    # bad/forged/expired signature.
    #
    # The webhook CONTROLLER + route are owned by the main builder; it calls
    # `Vendors::Stripe::Webhook.verify(payload, sig_header)` with the RAW body and
    # the header, then dispatches the returned event to
    # `Operations::Billing::SyncSubscription`.
    #
    # Signing secret: credential(:stripe, :webhook_secret) — ENV fallback
    # STRIPE_WEBHOOK_SECRET.
    #
    # See docs/integrations/stripe-billing.md §5.
    module Webhook
      module_function

      # Returns the verified Stripe::Event, or raises:
      #   ::Stripe::SignatureVerificationError — bad/expired signature
      #   Vendors::Base::NotConfiguredError    — missing signing secret
      def verify(payload, sig_header)
        ::Stripe::Webhook.construct_event(payload, sig_header, signing_secret)
      end

      def signing_secret
        secret = Vendors::Base.new.send(
          :credential, :stripe, :webhook_secret, env: "STRIPE_WEBHOOK_SECRET"
        )
        return secret if secret.present?

        raise Vendors::Base::NotConfiguredError,
              "Credencial ausente: stripe.webhook_secret. Configure em rails credentials:edit."
      end
    end
  end
end
