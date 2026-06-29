# frozen_string_literal: true

module Webhooks
  # Meta uses a GET handshake (hub.challenge) to verify the endpoint and POSTs
  # signed (X-Hub-Signature-256) event notifications.
  class MetaController < BaseController
    def handle
      return verify_subscription if request.get?

      status = Controllers::Webhooks::Meta::Receive.call(
        signature: request.headers["X-Hub-Signature-256"], payload: request.raw_post
      )
      head status
    rescue StandardError => e
      Rails.logger.warn("[Webhooks::Meta] #{e.message}")
      head :ok
    end

    private

    def verify_subscription
      challenge = Controllers::Webhooks::Meta::VerifySubscription.call(params: params)
      return render plain: challenge.to_s if challenge

      head :forbidden
    end
  end
end
