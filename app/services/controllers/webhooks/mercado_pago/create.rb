# frozen_string_literal: true

module Controllers
  module Webhooks
    module MercadoPago
      # Verifies the x-signature HMAC and enqueues the authoritative payment sync
      # (the body carries only the id — never trusted for state).
      class Create < Controllers::Base
        def initialize(headers:, payload:, query:)
          @headers = headers
          @payload = payload
          @query = query
        end

        def call
          result = Vendors::MercadoPago::Webhook.verify(@headers, @payload, query: @query)
          SyncMercadoPagoPaymentJob.perform_later(result.payment_id.to_s) if result.payment_id.present?
          result
        end
      end
    end
  end
end
