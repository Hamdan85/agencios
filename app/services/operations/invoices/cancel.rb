# frozen_string_literal: true

module Operations
  module Invoices
    # Cancels an invoice — and actually STOPS the collection:
    #   * a PAID invoice cannot be canceled (money already moved);
    #   * every still-pending Charge is locally voided (status `cancelled`), so
    #     the reconciliation sweep stops re-checking them, and
    #     SyncPaymentStatus's canceled guard keeps a late Pix payment from
    #     silently resurrecting the invoice as paid.
    #
    # Mercado Pago has no remote void for a Pix QR in our vendor surface, so a
    # client paying an already-canceled invoice is still possible — that event
    # is logged loudly by SyncPaymentStatus for manual refund handling.
    class Cancel < Operations::Base
      PENDING_STATUSES = %w[pending in_process authorized].freeze

      def initialize(invoice:)
        @invoice = invoice
      end

      def call
        raise Operations::Errors::Invalid, 'Uma fatura paga não pode ser cancelada.' if @invoice.status_paid?
        return @invoice if @invoice.status_canceled?

        @invoice.charges.where(status: PENDING_STATUSES).find_each do |charge|
          charge.update!(status: 'cancelled')
        end
        @invoice.update!(status: :canceled)
        @invoice
      end
    end
  end
end
