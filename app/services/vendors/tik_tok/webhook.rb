# frozen_string_literal: true

module Vendors
  module TikTok
    # TikTok webhook signature verification (§8). The webhook controller + route are
    # owned by the main builder — this provides the verify helper + envelope parser.
    #
    # Header: `TikTok-Signature: t=1633174587,s=<hex>`
    #   signed_payload = "{t}.{raw_request_body}"
    #   expected       = HMAC_SHA256(key = client_secret, message = signed_payload) (hex)
    # Constant-time compare expected vs s. The `content` field is a JSON *string* —
    # parse it. Events may be delivered more than once → handlers must be idempotent
    # (dedupe on publish_id + event).
    module Webhook
      module_function

      # Returns true iff the signature is valid for the raw body.
      def verify(raw_body, signature_header, secret)
        return false if signature_header.blank? || secret.blank?

        parts = parse_signature(signature_header)
        timestamp = parts['t']
        provided = parts['s']
        return false if timestamp.blank? || provided.blank?

        signed_payload = "#{timestamp}.#{raw_body}"
        expected = OpenSSL::HMAC.hexdigest('SHA256', secret, signed_payload)
        ActiveSupport::SecurityUtils.secure_compare(expected, provided)
      end

      # Parses the webhook envelope; `content` is a JSON string TikTok double-encodes.
      def parse_event(raw_body)
        envelope = JSON.parse(raw_body)
        content = envelope['content']
        envelope['content'] = JSON.parse(content) if content.is_a?(String)
        envelope
      end

      def parse_signature(header)
        header.split(',').each_with_object({}) do |pair, acc|
          key, value = pair.split('=', 2)
          acc[key.to_s.strip] = value.to_s.strip
        end
      end
    end
  end
end
