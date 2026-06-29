# frozen_string_literal: true

module Controllers
  module Invoices
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        invoice = workspace.invoices.find(@params[:id])
        invoice.update!(update_params)
        { invoice: serialize(invoice, InvoiceSerializer) }
      end

      private

      def update_params
        @params.require(:invoice).permit(:description, :due_date, :status, :amount_cents)
      end
    end
  end
end
