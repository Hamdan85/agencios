# frozen_string_literal: true

module Vendors
  module Meta
    # Meta (Instagram + Facebook) webhook verification (instagram.md §8 /
    # facebook.md §8). The webhook controller + route are owned by the main
    # builder — this provides the verify helpers.
    #
    # Two checks:
    #   1. GET handshake — Meta sends ?hub.mode=subscribe&hub.challenge=...&
    #      hub.verify_token=... ; confirm the verify token matches the configured
    #      one, then echo hub.challenge back as plain text (200). Use
    #      `verify_subscription(mode:, token:, challenge:)` → the challenge or nil.
    #   2. POST signature — every delivery is signed with
    #      `X-Hub-Signature-256: sha256=HMAC_SHA256(app_secret, raw_body)`.
    #      Verify against the RAW body bytes (re-serialized JSON breaks the HMAC).
    #      Use `verify(payload, signature)` → bool.
    module Webhook
      module_function

      SIGNATURE_HEADER = 'X-Hub-Signature-256'
      SIGNATURE_PREFIX = 'sha256='

      # Constant-time verify of the X-Hub-Signature-256 header against the raw
      # body. `signature` is the full header value ("sha256=<hex>"). `secret`
      # defaults to the Meta app secret. Returns true/false (never raises).
      def verify(payload, signature, secret = nil)
        secret ||= app_secret
        return false if payload.nil? || signature.blank? || secret.blank?

        provided = signature.to_s.delete_prefix(SIGNATURE_PREFIX)
        expected = OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, payload.to_s)
        ActiveSupport::SecurityUtils.secure_compare(expected, provided)
      rescue StandardError
        false
      end

      # GET subscription handshake. Returns the challenge string to echo when the
      # mode is "subscribe" and the verify token matches; otherwise nil.
      def verify_subscription(mode:, token:, challenge:, expected_token: nil)
        expected_token ||= verify_token
        return nil unless mode.to_s == 'subscribe'
        return nil if expected_token.blank?
        return nil unless ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected_token.to_s)

        challenge
      end

      # The full `sha256=<hex>` header value for a raw body (used in tests / when
      # signing outbound mock deliveries).
      def signature_for(payload, secret = nil)
        secret ||= app_secret
        "#{SIGNATURE_PREFIX}#{OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, payload.to_s)}"
      end

      def app_secret
        Rails.application.credentials.dig(:meta, :app_secret) || ENV['META_APP_SECRET']
      end

      def verify_token
        Rails.application.credentials.dig(:meta, :webhook_verify_token) ||
          ENV['META_WEBHOOK_VERIFY_TOKEN']
      end
    end
  end
end
