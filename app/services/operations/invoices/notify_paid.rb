# frozen_string_literal: true

module Operations
  module Invoices
    # Pushes a "cobrança paga" notification to the workspace's managers
    # (owner / admin / manager). Used by both the manual MarkPaid path and the
    # Mercado Pago webhook reconciliation (SyncPaymentStatus).
    class NotifyPaid < Operations::Base
      MANAGER_ROLES = %i[owner admin manager].freeze

      def initialize(invoice:)
        @invoice = invoice
      end

      def call
        managers.each do |manager|
          Operations::Push::Notify.call(
            user: manager,
            title: "Cobrança paga 💸",
            body: "#{@invoice.client&.name} — #{money(@invoice.amount_cents)}",
            path: "/cobrancas"
          )
        end

        email_client_receipt
      end

      private

      # Send the client a payment receipt (client-facing — not an app user).
      def email_client_receipt
        return if @invoice.client&.email.blank?

        InvoiceMailer.paid(invoice: @invoice).deliver_later
      rescue StandardError => e
        Rails.logger.warn("[Invoices::NotifyPaid] receipt email failed: #{e.message}")
      end

      def managers
        @invoice.workspace.memberships.where(role: MANAGER_ROLES).includes(:user).map(&:user)
      end

      def money(cents)
        "R$ #{format('%.2f', (cents || 0) / 100.0).tr('.', ',')}"
      end
    end
  end
end
