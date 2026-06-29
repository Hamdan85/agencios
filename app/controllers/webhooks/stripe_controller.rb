# frozen_string_literal: true

module Webhooks
  class StripeController < BaseController
    def create
      Controllers::Webhooks::Stripe::Create.call(
        payload: request.raw_post, signature: request.headers["Stripe-Signature"]
      )
      head :ok
    rescue StandardError => e
      Rails.logger.warn("[Webhooks::Stripe] rejected: #{e.message}")
      head :bad_request
    end
  end
end
