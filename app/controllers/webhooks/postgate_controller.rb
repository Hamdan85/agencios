# frozen_string_literal: true

module Webhooks
  # PostGate pushes post/profile lifecycle and analytics events here instead of
  # agencios polling (docs/integrations/postgate.md §5). No blanket rescue here
  # (unlike the Stripe/Mercado Pago handlers) — a missing webhook secret is a
  # misconfiguration and must crash loudly rather than be swallowed into a
  # generic 200/400; every other failure mode is already handled per-event
  # inside Controllers::Webhooks::Postgate::Receive, which always returns a
  # status.
  class PostgateController < BaseController
    def create
      status = Controllers::Webhooks::Postgate::Receive.call(
        signature: request.headers['X-PostGate-Signature'], payload: request.raw_post
      )
      head status
    end
  end
end
