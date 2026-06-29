# frozen_string_literal: true

module Controllers
  module Invoices
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        invoice = workspace.invoices.find(@params[:id])
        authorize!(invoice, :show?)
        { invoice: serialize(invoice, InvoiceSerializer) }
      end
    end
  end
end
