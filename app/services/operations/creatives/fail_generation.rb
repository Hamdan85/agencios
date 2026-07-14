# frozen_string_literal: true

module Operations
  module Creatives
    # Marks a generation (and its creative) failed and refunds any credits held
    # for it. Idempotent — a generation already terminal is left untouched (and
    # Refund itself is idempotent). Used by the video poll safety net + cancel.
    class FailGeneration < Operations::Base
      def initialize(generation:, reason: nil)
        @generation = generation
        @reason     = reason.to_s
      end

      def call
        return @generation if @generation.status_completed? || @generation.status_failed?

        # TODO(loss-mapping): we refund the customer's prepaid credits here, but the
        # PLATFORM may have already spent real vendor $ on the work that failed
        # (partial OpenRouter video scenes, Cartesia voice, a Banana image that
        # succeeded before a later step raised). That real cost is logged per call in
        # AiUsageLog. Build a report/metric of platform loss = SUM(AiUsageLog.cost_cents)
        # for generations that ended `failed` (and were refunded), sliced by kind +
        # provider + workspace, so we can see how much failures actually cost us.
        # description omitted → Credits::Refund records it via the localized
        # ledger key `credits.ledger.refund_failed_generation` (rendered per reader).
        Operations::Credits::Refund.call(generation: @generation)

        @generation.update!(status: :failed, failure_reason: @reason)
        @generation.creative&.update!(status: :failed)

        Broadcaster.generations(
          @generation.workspace_id, 'generation_failed',
          id: @generation.id, kind: @generation.kind, reason: @reason
        )
        # Also wake the ticket drawer (it follows ticket_<id>) so the failed
        # card replaces "Gerando…" without a manual refresh.
        if (ticket = @generation.creative&.ticket)
          Broadcaster.ticket(ticket, 'creative_failed', creative_id: @generation.creative_id)
        end
        # Halt the owning autopilot run, if any (rescued internally).
        Operations::Autopilot::OnGenerationSettled.call(generation: @generation)
        @generation
      rescue NameError
        # Broadcaster not loaded in some contexts — the state change still stands.
        @generation
      end
    end
  end
end
