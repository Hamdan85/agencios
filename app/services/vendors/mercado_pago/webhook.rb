# frozen_string_literal: true

require 'openssl'
require 'json'

module Vendors
  module MercadoPago
    # Verifies inbound Mercado Pago webhook notifications via the `x-signature`
    # HMAC, and extracts the payment id (`data.id`). The notification body carries
    # ONLY `data.id` — never trust it for state; the caller then does
    # GET /v1/payments/{id} (Operations::Billing::SyncPaymentStatus).
    #
    # x-signature algorithm (docs/integrations/mercado-pago.md §3):
    #   1. x-signature header: "ts=<ts>,v1=<hash>" — split into ts + v1.
    #   2. data.id comes from the QUERY STRING (?data.id=...). Lowercase it if
    #      alphanumeric (Orders ORD.../PAY... ids); numeric Pix ids unaffected.
    #   3. manifest = "id:<data.id>;request-id:<x-request-id>;ts:<ts>;"
    #      (trailing semicolon included; omit a segment only if its input absent).
    #   4. expected = HMAC_SHA256(secret, manifest) as hex.
    #   5. constant-time compare expected == v1.
    #
    # Secret: credential(:mercado_pago, :webhook_secret) / ENV
    # MERCADO_PAGO_WEBHOOK_SECRET (test secret != prod secret).
    module Webhook
      module_function

      Result = Struct.new(:valid, :payment_id, keyword_init: true) do
        def valid? = !!valid
      end

      # Verify a notification. `headers` is a hash-like of request headers (case-
      # insensitive lookups handled here). `raw_body` is the raw JSON string (used
      # only to recover `data.id` if it wasn't on the query string). `query` is the
      # parsed query-string hash (authoritative source of `data.id`).
      #
      # Returns a Result with #valid? and #payment_id.
      def verify(headers, raw_body = nil, query: {})
        signature = header(headers, 'x-signature').to_s
        request_id = header(headers, 'x-request-id').to_s
        ts, v1 = parse_signature(signature)
        payment_id = extract_data_id(query, raw_body)

        return Result.new(valid: false, payment_id: payment_id) if ts.blank? || v1.blank? || secret.blank?

        manifest = build_manifest(data_id: normalize_id(payment_id), request_id: request_id, ts: ts)
        expected = OpenSSL::HMAC.hexdigest('SHA256', secret, manifest)
        valid = ActiveSupport::SecurityUtils.secure_compare(expected, v1)

        Result.new(valid: valid, payment_id: payment_id)
      end

      # --- internals ----------------------------------------------------------

      def secret
        Rails.application.credentials.dig(:mercado_pago, :webhook_secret) ||
          ENV['MERCADO_PAGO_WEBHOOK_SECRET']
      end

      # "ts=123,v1=abc" => ["123", "abc"]
      def parse_signature(signature)
        parts = signature.split(',').each_with_object({}) do |segment, acc|
          key, value = segment.split('=', 2)
          acc[key.to_s.strip] = value.to_s.strip if key && value
        end
        [parts['ts'], parts['v1']]
      end

      # data.id is authoritative from the query string; fall back to the body.
      def extract_data_id(query, raw_body)
        id = query_data_id(query)
        return id if id.present?

        body_data_id(raw_body)
      end

      def query_data_id(query)
        return nil if query.blank?

        query['data.id'] || query[:data_id] || query.dig('data', 'id')
      end

      def body_data_id(raw_body)
        return nil if raw_body.blank?

        parsed = raw_body.is_a?(String) ? JSON.parse(raw_body) : raw_body
        parsed.is_a?(Hash) ? parsed.dig('data', 'id') : nil
      rescue JSON::ParserError
        nil
      end

      # MP lowercases alphanumeric ids before signing (Orders); numeric Pix ids
      # are unaffected by lowercasing.
      def normalize_id(id)
        id = id.to_s
        id.match?(/[a-z]/i) ? id.downcase : id
      end

      # Build the manifest, omitting a segment only when its input is blank.
      def build_manifest(data_id:, request_id:, ts:)
        manifest = +''
        manifest << "id:#{data_id};" if data_id.present?
        manifest << "request-id:#{request_id};" if request_id.present?
        manifest << "ts:#{ts};" if ts.present?
        manifest
      end

      # Case-insensitive header lookup over a plain Hash or a Rails headers object.
      def header(headers, name)
        return nil if headers.nil?

        if headers.respond_to?(:[]) && headers[name]
          headers[name]
        elsif headers.respond_to?(:each)
          _, value = headers.find { |k, _| k.to_s.downcase == name.downcase }
          value
        end
      end
    end
  end
end
