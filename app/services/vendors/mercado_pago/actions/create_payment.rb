# frozen_string_literal: true

require "securerandom"

module Vendors
  module MercadoPago
    module Actions
      # POST /v1/payments — create a Pix (default), boleto, or card payment for an
      # invoice (Checkout Transparente / Payments API). The classic Payments API
      # response carries the Pix QR under `point_of_interaction.transaction_data`.
      #
      # See docs/integrations/mercado-pago.md §2 (Pix/boleto/card request shapes).
      #
      #   Vendors::MercadoPago::Actions::CreatePayment.call(
      #     invoice: invoice, method: :pix, payer: { email: "client@example.com" }
      #   )
      #
      # `method` accepts :pix (default), :boleto, or :card. For card, pass the
      # one-time `card_token` (and optionally installments/payment_method_id/
      # issuer_id) — tokenization happens on the frontend with the public key.
      class CreatePayment
        def self.call(...) = new(...).call

        # Maps our domestic method to MP's `payment_method_id`. Pix and boleto are
        # fixed strings; card's brand id comes from the tokenization step (passed
        # explicitly), defaulting to "master" only as a placeholder.
        PAYMENT_METHOD_IDS = {
          pix: "pix",
          boleto: "bolbradesco",
          card: nil
        }.freeze

        def initialize(invoice:, payer:, method: :pix, client: nil,
                       card_token: nil, installments: 1, payment_method_id: nil,
                       issuer_id: nil, idempotency_key: nil, expires_at: nil, extra: {})
          @invoice = invoice
          @payer = payer
          @method = method.to_sym
          @client = client || Vendors::MercadoPago::Client.new(workspace: invoice.workspace)
          @card_token = card_token
          @installments = installments
          @payment_method_id = payment_method_id
          @issuer_id = issuer_id
          @idempotency_key = idempotency_key || SecureRandom.uuid
          @expires_at = expires_at
          @extra = extra
        end

        # Returns the parsed MP payment body. For Pix, read the QR from
        # `point_of_interaction.transaction_data.{qr_code,qr_code_base64,ticket_url}`;
        # for boleto, the printable URL from
        # `transaction_details.external_resource_url`.
        def call
          @client.create_payment(body: body, idempotency_key: @idempotency_key)
        end

        private

        def body
          base = {
            transaction_amount: transaction_amount,
            description: description,
            external_reference: @invoice.external_reference,
            notification_url: notification_url,
            payer: @payer
          }
          base[:date_of_expiration] = expiration_iso if expiration_iso
          base.merge!(method_fields)
          base.merge!(@extra)
          base
        end

        # MP wants BRL as a decimal amount, not cents.
        def transaction_amount
          @invoice.amount_cents / 100.0
        end

        def description
          @invoice.description.presence || "Invoice #{@invoice.id}"
        end

        # The webhook endpoint MP calls with the payment id (per-app notification).
        def notification_url
          "#{SystemConfig.app_host}/webhooks/mercadopago"
        end

        # Per-method request fields (payment_method_id, plus card token data).
        def method_fields
          case @method
          when :pix, :boleto
            { payment_method_id: PAYMENT_METHOD_IDS.fetch(@method) }
          when :card
            {
              token: @card_token,
              installments: @installments,
              payment_method_id: @payment_method_id,
              issuer_id: @issuer_id
            }.compact
          else
            raise ArgumentError, "Unsupported payment method: #{@method.inspect}"
          end
        end

        # Pix QR expiry / boleto due date. Prefer an explicit override, else the
        # invoice due date (end of that day, BRT), else MP's default.
        def expiration_iso
          return @expires_at.iso8601(3) if @expires_at.respond_to?(:iso8601)
          return @expires_at if @expires_at.is_a?(String)
          return nil unless @invoice.due_date

          @invoice.due_date.end_of_day.in_time_zone("America/Sao_Paulo").iso8601(3)
        end
      end
    end
  end
end
