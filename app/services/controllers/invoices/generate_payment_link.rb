# frozen_string_literal: true

module Controllers
  module Invoices
    # POST /api/v1/invoices/:id/payment_link — generate a hosted payment link for
    # the invoice (today via Mercado Pago Checkout Pro).
    class GeneratePaymentLink < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        invoice = workspace.invoices.find(@params[:id])
        Operations::Billing::GeneratePaymentLink.call(invoice: invoice)
        { invoice: serialize(invoice.reload, InvoiceSerializer) }
      end
    end
  end
end
