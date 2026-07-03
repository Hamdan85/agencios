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
        # Status is NOT editable here — transitions go through the dedicated
        # actions (send_invoice / cancel / mark_paid); the editability + amount
        # lock rules live in Operations::Invoices::Update.
        Operations::Invoices::Update.call(invoice: invoice, attributes: update_params)
        { invoice: serialize(invoice.reload, InvoiceSerializer) }
      end

      private

      def update_params
        @params.require(:invoice).permit(:description, :due_date, :amount_cents)
      end
    end
  end
end
