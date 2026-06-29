# frozen_string_literal: true

module Controllers
  module Invoices
    # POST /api/v1/invoices/:id/send_invoice — move a draft to `open`.
    class SendInvoice < Base
      def initialize(params:)
        @params = params
      end

      def call
        invoice = workspace.invoices.find(@params[:id])
        invoice.update!(status: :open)
        { invoice: serialize(invoice, InvoiceSerializer) }
      end
    end
  end
end
