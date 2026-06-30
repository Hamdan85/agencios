# frozen_string_literal: true

module Controllers
  module Webhooks
    module Social
      # POST event notification for the Instagram-Login and Threads webhook
      # endpoints. Each is signed with X-Hub-Signature-256 = HMAC-SHA256 over the
      # raw body, keyed by that product's OWN app secret (Instagram/Threads apps
      # have separate secrets from the Facebook app). Returns the HTTP status to
      # head (:unauthorized on a bad signature).
      #
      # Event routing (deauthorize, comments, mentions, replies) is a follow-up —
      # this verifies + acknowledges, matching the existing Meta webhook maturity.
      class Receive < Controllers::Base
        def initialize(provider:, signature:, payload:)
          @provider = provider.to_s
          @signature = signature
          @payload = payload
        end

        def call
          secret = resolve_secret
          return :not_found if secret.blank?
          return :unauthorized unless Vendors::Meta::Webhook.verify(@payload, @signature, secret)

          :ok
        end

        private

        # The product-specific app secret used to verify the delivery signature.
        def resolve_secret
          key, env =
            case @provider
            when "instagram" then [:instagram_app_secret, "INSTAGRAM_APP_SECRET"]
            when "threads"   then [:threads_app_secret, "THREADS_APP_SECRET"]
            end
          return nil unless key

          Rails.application.credentials.dig(:meta, key) || ENV[env]
        end
      end
    end
  end
end
