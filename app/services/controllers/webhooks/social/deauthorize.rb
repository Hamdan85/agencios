# frozen_string_literal: true

module Controllers
  module Webhooks
    module Social
      # Handles a Meta-family **Deauthorize Callback** (App/Product Settings →
      # "Deauthorize Callback URL"). When a user removes our app, Meta POSTs a
      # `signed_request` ("<base64url sig>.<base64url payload>") signed with that
      # product's app secret; the payload carries the app-scoped `user_id`. We
      # verify, then revoke that user's accounts for the provider.
      #
      # Per-provider app secret (each product has its own):
      #   facebook → app_secret · instagram → instagram_app_secret ·
      #   threads → threads_app_secret.
      class Deauthorize < Controllers::Base
        def initialize(provider:, signed_request:)
          @provider = provider.to_s
          @signed_request = signed_request.to_s
        end

        def call
          secret = resolve_secret
          return 0 if secret.blank?

          data = parse_signed_request(@signed_request, secret)
          user_id = data && data["user_id"]
          return 0 if user_id.blank?

          Operations::Social::Deauthorize.call(providers: [@provider], external_user_id: user_id)
        end

        private

        def resolve_secret
          key, env =
            case @provider
            when "facebook"  then [:app_secret, "META_APP_SECRET"]
            when "instagram" then [:instagram_app_secret, "INSTAGRAM_APP_SECRET"]
            when "threads"   then [:threads_app_secret, "THREADS_APP_SECRET"]
            end
          return nil unless key

          Rails.application.credentials.dig(:meta, key) || ENV[env]
        end

        # Verify "<sig>.<payload>" (base64url) — HMAC-SHA256(secret, payload) must
        # match the decoded sig. Returns the parsed payload Hash, or nil.
        def parse_signed_request(signed_request, secret)
          encoded_sig, payload = signed_request.split(".", 2)
          return nil if encoded_sig.blank? || payload.blank?

          expected = OpenSSL::HMAC.digest("SHA256", secret.to_s, payload)
          provided = base64_url_decode(encoded_sig)
          return nil unless ActiveSupport::SecurityUtils.secure_compare(expected, provided)

          JSON.parse(base64_url_decode(payload))
        rescue StandardError
          nil
        end

        def base64_url_decode(str)
          padded = str.tr("-_", "+/")
          padded += "=" * ((4 - (padded.length % 4)) % 4)
          Base64.decode64(padded)
        end
      end
    end
  end
end
