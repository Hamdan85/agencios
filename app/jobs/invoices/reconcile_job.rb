# frozen_string_literal: true

module Invoices
  # Scheduled reconciliation sweep for Mercado Pago payments.
  #
  # Pix payments can be paid WITHOUT a prompt webhook (delayed/dropped
  # notifications), so this catches them: for every pending Charge with an MP
  # payment id from the last N days, re-read the authoritative status via
  # Operations::Billing::SyncPaymentStatus (which moves the Invoice forward only).
  #
  # Idempotent and safe to run on a sidekiq-cron schedule alongside live webhooks.
  class ReconcileJob < ApplicationJob
    queue_as :low

    # MP status strings that are still in flight and worth re-checking.
    PENDING_STATUSES = %w[pending in_process authorized].freeze
    DEFAULT_LOOKBACK_DAYS = 7

    def perform(lookback_days: DEFAULT_LOOKBACK_DAYS)
      pending_charges(lookback_days).find_each do |charge|
        Operations::Billing::SyncPaymentStatus.call(
          payment_id: charge.mp_payment_id,
          workspace: charge.workspace
        )
      rescue Vendors::Base::Error => e
        # One bad charge must not abort the sweep — log and continue.
        Rails.logger.warn("[Invoices::ReconcileJob] charge #{charge.id} sync failed: #{e.message}")
      end
    end

    private

    def pending_charges(lookback_days)
      Charge
        .where(status: PENDING_STATUSES)
        .where.not(mp_payment_id: nil)
        .where(created_at: lookback_days.days.ago..)
    end
  end
end
