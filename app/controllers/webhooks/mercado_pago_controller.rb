# frozen_string_literal: true

module Webhooks
  # Mercado Pago webhooks carry only the payment id — we always reconcile via
  # GET /v1/payments/{id} (never trust the body). Verify the x-signature HMAC,
  # then enqueue the authoritative status sync.
  class MercadoPagoController < BaseController
    def create
      Controllers::Webhooks::MercadoPago::Create.call(
        headers: request.headers, payload: request.raw_post, query: request.query_parameters
      )
      head :ok
    rescue StandardError => e
      Rails.logger.warn("[Webhooks::MercadoPago] #{e.message}")
      head :ok # always 200 — MP retries aggressively; the sweep catches misses
    end
  end
end
