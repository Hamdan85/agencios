# frozen_string_literal: true

module Operations
  module Invoices
    # Manually settles an invoice (e.g. the client paid out-of-band — cash,
    # transfer). Marks the invoice paid and closes the latest charge, if any.
    # Provider webhooks reach the same end state via Operations::Billing::
    # SyncPaymentStatus.
    class MarkPaid < Operations::Base
      def initialize(invoice:)
        @invoice = invoice
      end

      def call
        was_paid = @invoice.status_paid?
        @invoice.update!(status: :paid)
        @invoice.latest_charge&.update!(status: "approved")
        Operations::Invoices::NotifyPaid.call(invoice: @invoice) unless was_paid
        @invoice
      end
    end
  end
end
