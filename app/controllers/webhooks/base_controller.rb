# frozen_string_literal: true

module Webhooks
  # Inbound vendor webhooks. Signature verification + enqueuing the right
  # reconciliation operation is done per-provider; these acknowledge fast (200)
  # and never trust the payload body for authoritative state.
  class BaseController < ActionController::API
    def acknowledge
      head :ok
    end
  end
end
