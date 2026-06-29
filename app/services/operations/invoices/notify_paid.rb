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
      end

      private

      def managers
        @invoice.workspace.memberships.where(role: MANAGER_ROLES).includes(:user).map(&:user)
      end

      def money(cents)
        "R$ #{format('%.2f', (cents || 0) / 100.0).tr('.', ',')}"
      end
    end
  end
end
