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

        Operations::Credits::Refund.call(generation: @generation, description: 'Estorno — geração falhou')

        @generation.update!(status: :failed, failure_reason: @reason)
        @generation.creative&.update!(status: :failed)

        Broadcaster.generations(
          @generation.workspace_id, 'generation_failed',
          id: @generation.id, kind: @generation.kind, reason: @reason
        )
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
