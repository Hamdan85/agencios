# frozen_string_literal: true

module Vendors
  module Heygen
    # Inbound-webhook signature verification.
    #
    # HeyGen signs each delivery with the `Heygen-Signature` header — a
    # hex-encoded HMAC-SHA256 of the RAW request body, computed with the endpoint
    # `secret` returned (once) at endpoint creation/rotation. Verify against the
    # raw body bytes (re-serialized JSON breaks the HMAC). Supporting headers:
    # `Heygen-Timestamp` (reject stale, ~5-min window) and `Heygen-Event-Id`
    # (dedupe retries). See docs/integrations/heygen.md §3e.
    module Webhook
      module_function

      SIGNATURE_HEADER = 'Heygen-Signature'
      TIMESTAMP_HEADER = 'Heygen-Timestamp'
      EVENT_ID_HEADER  = 'Heygen-Event-Id'

      # Constant-time compare of the computed HMAC against the supplied signature.
      # `payload` is the RAW request body string; `signature` is the
      # `Heygen-Signature` header value. `secret` defaults to the configured
      # webhook secret. Returns true/false (never raises).
      def verify(payload, signature, secret = nil)
        secret ||= webhook_secret
        return false if payload.nil? || signature.blank? || secret.blank?

        expected = OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, payload.to_s)
        ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
      rescue StandardError
        false
      end

      # Optional staleness guard: reject deliveries older than `tolerance`.
      def fresh?(timestamp, tolerance: 5.minutes)
        return true if timestamp.blank?

        sent_at = Integer(timestamp)
        (Time.current.to_i - sent_at).abs <= tolerance.to_i
      rescue ArgumentError, TypeError
        false
      end

      def webhook_secret
        Rails.application.credentials.dig(:heygen, :webhook_secret) || ENV['HEYGEN_WEBHOOK_SECRET']
      end
    end
  end
end
