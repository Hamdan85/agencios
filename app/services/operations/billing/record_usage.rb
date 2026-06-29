# frozen_string_literal: true

module Operations
  module Billing
    # Report a completed billable generation to Stripe's Billing Meters, then
    # stamp it locally as metered. Called when a carousel/video generation
    # completes (typically from a Sidekiq job so a Stripe outage never blocks the
    # user's generation).
    #
    # Idempotent on two layers:
    #   1. local — skips if the generation is image kind or already `metered_at`;
    #   2. Stripe — ReportMeterEvent uses a deterministic identifier so a retry
    #      within Stripe's dedup window is never double-counted.
    #
    # Workspaces without a `stripe_customer_id` (free/internal, not yet checked
    # out) are skipped — there is nothing to bill.
    #
    # See docs/integrations/stripe-billing.md §4.
    class RecordUsage < Operations::Base
      def initialize(generation)
        @generation = generation
      end

      def call
        return :not_billable unless @generation.billable?
        return :already_metered if @generation.metered?

        subscription = @generation.workspace.subscription
        return :no_customer if subscription&.stripe_customer_id.blank?

        Vendors::Stripe::Actions::ReportMeterEvent.call(@generation)
        @generation.update!(metered_at: Time.current)
        :metered
      end
    end
  end
end
