# frozen_string_literal: true

module Operations
  module Autopilot
    # Re-enters the engine when an async generation reaches a terminal state.
    # Called from inside Operations::Video::Compose / FailGeneration (the RELIABLE seam —
    # broadcasts are fire-and-forget and can be dropped). Also used by the watchdog
    # and by Advance's `awaiting_generation` branch via `.reconcile`.
    #
    # Re-derives from the tracked Generation rows under a row lock (never trusts an
    # event payload), so duplicate webhook + poll delivery is safe.
    class OnGenerationSettled < Operations::Base
      def initialize(generation:)
        @generation = generation
      end

      def call
        ticket = @generation.creative&.ticket
        return unless ticket

        run = AutopilotRun.ticket_runs.where(state: 'awaiting_generation').find_by(ticket_id: ticket.id)
        return unless run

        self.class.reconcile(run: run)
      rescue StandardError => e
        Rails.logger.warn("[Autopilot::OnGenerationSettled] gen #{@generation&.id}: #{e.message}")
        nil
      end

      # Inspect the run's tracked generations and move it forward:
      #   * any failed  → halt the run (per-generation refund already happened)
      #   * none pending → advance to publishing
      #   * still pending → stay put
      def self.reconcile(run:)
        action = nil
        run.with_lock do
          break unless run.state == 'awaiting_generation'

          gens = Generation.where(id: run.generation_ids).to_a
          pending = gens.select { |g| g.status_queued? || g.status_processing? }
          if gens.any?(&:status_failed?)
            action = :fail
          elsif pending.empty?
            action = :complete
          end
        end

        case action
        when :complete then Operations::Autopilot::Complete.call(run: run)
        when :fail     then Operations::Autopilot::Fail.call(run: run, reason: 'Uma geração de criativo falhou.')
        end
        run
      end
    end
  end
end
