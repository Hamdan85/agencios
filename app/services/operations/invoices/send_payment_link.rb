# frozen_string_literal: true

module Operations
  module Invoices
    # Explicitly emails the client the invoice's payment link — from the
    # invoice list, the creation success dialog, or the "Iniciar cobrança"
    # flow on a finalized project. Generates the link first if one doesn't
    # already exist (or the existing one is settled); safe to call again as
    # a resend.
    class SendPaymentLink < Operations::Base
      def initialize(invoice:)
        @invoice = invoice
      end

      def call
        raise Operations::Errors::Invalid, "Cliente sem e-mail cadastrado." if @invoice.client&.email.blank?

        charge = existing_open_charge || Operations::Billing::GeneratePaymentLink.call(invoice: @invoice)
        InvoiceMailer.payment_link(invoice: @invoice, payment_url: charge.payment_link).deliver_later
        charge
      end

      private

      def existing_open_charge
        charge = @invoice.latest_charge
        charge if charge&.payment_link.present? && !charge.paid?
      end
    end
  end
end
