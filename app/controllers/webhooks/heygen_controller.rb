# frozen_string_literal: true

module Webhooks
  # HeyGen fires when an async video render completes/fails. We verify the
  # signature, find the Generation by external_id, and finalize it (download +
  # attach + meter).
  class HeygenController < BaseController
    def create
      status = Controllers::Webhooks::Heygen::Create.call(
        signature: request.headers['Heygen-Signature'],
        timestamp: request.headers['Heygen-Timestamp'],
        payload: request.raw_post,
        params: params
      )
      head status
    rescue StandardError => e
      Rails.logger.warn("[Webhooks::Heygen] #{e.message}")
      head :ok
    end
  end
end
