# frozen_string_literal: true

module Operations
  module Invoices
    # Edits an invoice's own fields. Status is NEVER edited here — transitions
    # go through their dedicated operations (Send, Cancel, MarkPaid), so a paid
    # invoice can't be dragged back to draft by a plain PATCH.
    #
    # The amount is the contract with the payment link: once any Charge exists
    # (a Pix QR / boleto is out with the OLD amount), changing it would desync
    # what the client pays from what the invoice says — locked from then on.
    class Update < Operations::Base
      # Paid and canceled invoices are immutable records; overdue stays editable
      # (pushing the due date of a late invoice is a legitimate move).
      EDITABLE_STATUSES = %w[draft open overdue].freeze

      def initialize(invoice:, attributes:)
        @invoice = invoice
        @attributes = attributes.to_h.symbolize_keys.slice(:description, :due_date, :amount_cents)
      end

      def call
        unless EDITABLE_STATUSES.include?(@invoice.status)
          raise Operations::Errors::Invalid, 'Faturas pagas ou canceladas não podem ser editadas.'
        end

        if @attributes.key?(:amount_cents) && changing_amount? && @invoice.charges.exists?
          raise Operations::Errors::Invalid,
                'O valor não pode mudar depois de uma cobrança gerada — cancele a fatura e crie outra.'
        end

        @invoice.update!(@attributes)
        @invoice
      end

      private

      def changing_amount?
        @attributes[:amount_cents].to_i != @invoice.amount_cents.to_i
      end
    end
  end
end
