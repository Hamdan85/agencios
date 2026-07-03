# frozen_string_literal: true

module Operations
  module Billing
    # Reconcile a Mercado Pago payment's authoritative status onto our records.
    #
    # Webhooks carry only `data.id` (never trustworthy state), and may arrive
    # duplicated, out of order, or delayed — so this:
    #   1. GET /v1/payments/{id} (authoritative — never trusts a webhook body),
    #   2. finds the Charge by mp_payment_id,
    #   3. updates charge.status to MP's status,
    #   4. moves the Invoice FORWARD only (approved => paid; rejected/cancelled
    #      handled), never backward.
    #
    # Idempotent: safe to run repeatedly from the webhook AND the scheduled
    # reconciliation sweep (Pix can be paid without a prompt webhook).
    #
    #   Operations::Billing::SyncPaymentStatus.call(payment_id: "999", workspace: ws)
    class SyncPaymentStatus < Operations::Base
      # MP status values that mean "money received" (Invoice -> paid).
      APPROVED_STATUSES = %w[approved].freeze
      # MP status values that mean the attempt failed/was voided.
      FAILED_STATUSES = %w[rejected cancelled].freeze

      def initialize(payment_id:, workspace: nil)
        @payment_id = payment_id.to_s
        @workspace = workspace
      end

      def call
        return if @payment_id.blank?

        payment = fetch_payment
        charge = find_charge(payment)
        return unless charge

        new_status = payment['status'].to_s.presence
        return charge if new_status.blank?

        update_charge(charge, new_status, payment)
        advance_invoice(charge.invoice, new_status)
        charge
      end

      private

      # Authoritative status read — never trust the webhook body.
      def fetch_payment
        Vendors::MercadoPago::Actions::GetPayment.call(@payment_id, workspace: @workspace)
      end

      # Locate the Charge by the MP payment id. Fall back to external_reference
      # (the invoice id we persist) so a charge created before the id was stored
      # still reconciles.
      def find_charge(payment)
        charge = charge_scope.find_by(mp_payment_id: @payment_id)
        return charge if charge

        reference = payment['external_reference'].to_s
        return nil if reference.blank?

        invoice = invoice_scope.find_by(external_reference: reference)
        invoice&.latest_charge&.tap { |c| c.update!(mp_payment_id: @payment_id) if c.mp_payment_id.blank? }
      end

      # Persist MP's status verbatim onto the charge (idempotent — a repeat write
      # of the same value is a no-op as far as state is concerned).
      def update_charge(charge, new_status, payment)
        attrs = { status: new_status }
        attrs[:expires_at] = parse_time(payment['date_of_expiration']) if payment['date_of_expiration'].present?
        charge.update!(attrs)
      end

      # Move the invoice forward only. approved => paid; rejected/cancelled =>
      # overdue/canceled are NOT auto-applied here (a failed attempt doesn't void
      # an invoice — the client can retry), so we only ever advance to :paid.
      #
      # A CANCELED invoice never resurrects: MP has no remote void for a Pix QR,
      # so a client can still pay one that's already canceled — the money event
      # is logged loudly for manual refund handling, but the invoice stays
      # canceled (the charge itself was updated above, so the payment is on
      # record).
      def advance_invoice(invoice, new_status)
        return unless invoice
        return unless APPROVED_STATUSES.include?(new_status)
        return if invoice.status_paid?

        if invoice.status_canceled?
          Rails.logger.error(
            "[Billing::SyncPaymentStatus] payment #{@payment_id} APPROVED for CANCELED " \
            "invoice ##{invoice.id} (workspace #{invoice.workspace_id}) — needs manual refund"
          )
          return
        end

        invoice.update!(status: :paid)
        Operations::Invoices::NotifyPaid.call(invoice: invoice)
        track_client_invoice_paid(invoice)
      end

      # Agency-side revenue: a client paid an invoice via Mercado Pago. Captured
      # once on the paid edge (the `status_paid?` guard above makes it idempotent
      # across repeat webhooks + the reconciliation sweep). Keyed on the workspace
      # owner + grouped by workspace, matching the SPA identify. Server-only — the
      # browser never sees the payment, so PostHog never double-counts it.
      def track_client_invoice_paid(invoice)
        owner = invoice.workspace&.owner
        return unless owner

        Vendors::Posthog::Actions::Capture.call(
          user: owner, event: 'client_invoice_paid',
          properties: { amount_cents: invoice.amount_cents, currency: invoice.currency },
          groups: { workspace: invoice.workspace_id }
        )
      end

      def charge_scope
        @workspace ? Charge.where(workspace_id: @workspace.id) : Charge
      end

      def invoice_scope
        @workspace ? @workspace.invoices : Invoice
      end

      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
