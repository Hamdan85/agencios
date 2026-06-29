# frozen_string_literal: true

module Controllers
  module Webhooks
    module Meta
      # POST event notification — verifies the X-Hub-Signature-256 HMAC. Returns
      # the HTTP status symbol to head (:unauthorized on a bad signature).
      # Real-time comment/mention/metric fan-out would happen here.
      class Receive < Controllers::Base
        def initialize(signature:, payload:)
          @signature = signature
          @payload = payload
        end

        def call
          return :unauthorized unless Vendors::Meta::Webhook.verify(@payload, @signature)

          :ok
        end
      end
    end
  end
end
