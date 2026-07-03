# frozen_string_literal: true

module Controllers
  module Invoices
    # POST /api/v1/invoices/:id/send_invoice — the draft-only rule lives in
    # Operations::Invoices::Send.
    class SendInvoice < Base
      def initialize(params:)
        @params = params
      end

      def call
        invoice = workspace.invoices.find(@params[:id])
        Operations::Invoices::Send.call(invoice: invoice)
        { invoice: serialize(invoice.reload, InvoiceSerializer) }
      end
    end
  end
end
