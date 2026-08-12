# frozen_string_literal: true

module Vendors
  module Postgate
    # PostGate webhook signature verification (docs/integrations/postgate.md §5).
    #
    # Header: `X-PostGate-Signature: t=<unix_ts>,v1=<hex_hmac>` where
    #   hex_hmac = HMAC_SHA256(webhook_secret, "<t>.<raw_request_body>")
    # Same timestamped-HMAC shape as Stripe/Mercado Pago elsewhere in this
    # codebase — reject a stale timestamp to guard against replay, and always
    # compare with ActiveSupport::SecurityUtils.secure_compare, never `==`.
    module Webhook
      module_function

      MAX_SKEW = 5.minutes

      def secret
        Rails.application.credentials.dig(:postgate, :webhook_secret) || ENV['POSTGATE_WEBHOOK_SECRET']
      end

      # Returns true iff the signature is valid AND the timestamp is within
      # MAX_SKEW of now. Raises Vendors::Base::NotConfiguredError when no webhook
      # secret is configured — a misconfiguration, not a bad request, so it
      # crashes loudly instead of silently rejecting every delivery as unauthorized.
      def verify(raw_body, signature_header)
        key = secret
        raise Vendors::Base::NotConfiguredError, 'postgate.webhook_secret' if key.blank?
        return false if signature_header.blank?

        ts, provided = parse_signature(signature_header)
        return false if ts.blank? || provided.blank? || stale?(ts)

        expected = OpenSSL::HMAC.hexdigest('SHA256', key, "#{ts}.#{raw_body}")
        ActiveSupport::SecurityUtils.secure_compare(expected, provided)
      end

      # "t=123,v1=abc" => ["123", "abc"]
      def parse_signature(header)
        parts = header.split(',').each_with_object({}) do |segment, acc|
          key, value = segment.split('=', 2)
          acc[key.to_s.strip] = value.to_s.strip if key && value
        end
        [parts['t'], parts['v1']]
      end

      def stale?(ts)
        time = Time.zone.at(Integer(ts))
        (Time.current - time).abs > MAX_SKEW
      rescue ArgumentError, TypeError
        true
      end
    end
  end
end
