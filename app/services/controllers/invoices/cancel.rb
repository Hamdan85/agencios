# frozen_string_literal: true

module Controllers
  module Invoices
    # POST /api/v1/invoices/:id/cancel
    class Cancel < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        invoice = workspace.invoices.find(@params[:id])
        invoice.update!(status: :canceled)
        { invoice: serialize(invoice, InvoiceSerializer) }
      end
    end
  end
end
