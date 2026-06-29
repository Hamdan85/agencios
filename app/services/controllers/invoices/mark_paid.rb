# frozen_string_literal: true

module Controllers
  module Invoices
    # POST /api/v1/invoices/:id/mark_paid — manually settle the invoice.
    class MarkPaid < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        invoice = workspace.invoices.find(@params[:id])
        Operations::Invoices::MarkPaid.call(invoice: invoice)
        { invoice: serialize(invoice.reload, InvoiceSerializer) }
      end
    end
  end
end
