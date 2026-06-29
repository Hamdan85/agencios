# frozen_string_literal: true

module Vendors
  module MercadoPago
    module Actions
      # POST /checkout/preferences — create a hosted Checkout Pro payment link.
      # Use only for the "send a link" case (zero UI); Pix-first uses CreatePayment.
      # The response's `init_point` is the URL the client is redirected to.
      #
      # For marketplace (multi-tenant) the preference is created with the agency's
      # OAuth token (pass the invoice's workspace) and may carry a `marketplace_fee`.
      #
      # See docs/integrations/mercado-pago.md §2d.
      #
      #   Vendors::MercadoPago::Actions::CreatePreference.call(
      #     invoice: invoice, payer: { email: "client@example.com" }
      #   )
      #   # => { "id" => ..., "init_point" => "https://...", "sandbox_init_point" => "..." }
      class CreatePreference
        def self.call(...) = new(...).call

        def initialize(invoice:, payer:, client: nil, marketplace_fee: nil,
                       back_urls: nil, auto_return: "approved", extra: {})
          @invoice = invoice
          @payer = payer
          @client = client || Vendors::MercadoPago::Client.new(workspace: invoice.workspace)
          @marketplace_fee = marketplace_fee
          @back_urls = back_urls
          @auto_return = auto_return
          @extra = extra
        end

        def call
          @client.create_preference(body: body)
        end

        private

        def body
          base = {
            items: [{
              title: title,
              quantity: 1,
              unit_price: unit_price,
              currency_id: @invoice.currency.presence || "BRL"
            }],
            payer: @payer,
            external_reference: @invoice.external_reference,
            notification_url: notification_url,
            back_urls: @back_urls || default_back_urls,
            auto_return: @auto_return
          }
          base[:marketplace_fee] = @marketplace_fee if @marketplace_fee
          base.merge!(@extra)
          base
        end

        def title
          @invoice.description.presence || "Invoice #{@invoice.id}"
        end

        # Checkout Pro takes a BRL decimal unit price, not cents.
        def unit_price
          @invoice.amount_cents / 100.0
        end

        def notification_url
          "#{SystemConfig.app_host}/webhooks/mercadopago"
        end

        def default_back_urls
          base = "#{SystemConfig.app_host}/cobrancas/#{@invoice.id}"
          {
            success: "#{base}?paid=1",
            pending: base,
            failure: "#{base}?failed=1"
          }
        end
      end
    end
  end
end
