# frozen_string_literal: true

module Operations
  module Autopilot
    # Halts a run. A hard vendor failure (or a mid-run credit shortfall) stops the
    # walk rather than looping forever — the ticket keeps whatever creatives were
    # produced for manual completion, and the user is told which run failed and why.
    # Per-generation credits were already refunded by FailGeneration; successful
    # creatives' credits stay spent (once in motion, they're spent).
    class Fail < Operations::Base
      def initialize(run:, reason: nil)
        @run = run
        @reason = reason.to_s.presence
      end

      def call
        halted = false
        @run.with_lock do
          break if @run.terminal?

          @run.update!(state: 'failed', failure_reason: @reason, finished_at: Time.current)
          halted = true
        end
        return @run unless halted

        broadcast
        notify_owner
        Operations::Autopilot::RecomputeBatch.call(batch_id: @run.batch_id) if @run.batch_id
        @run
      end

      private

      def broadcast
        return unless @run.ticket

        Broadcaster.ticket(@run.ticket, 'autopilot_failed', run_id: @run.id, reason: @reason)
        Broadcaster.board(@run.workspace_id, 'autopilot_failed', ticket_id: @run.ticket_id, run_id: @run.id)
      end

      def notify_owner
        return if @run.user.nil? || @run.ticket.nil?

        Operations::Push::Notify.call(
          user: @run.user,
          title: 'Piloto automático interrompido',
          body: "#{@run.ticket.display_title}: #{@reason || 'a geração não pôde ser concluída.'}",
          path: "/tickets/#{@run.ticket_id}"
        )
      rescue StandardError => e
        Rails.logger.warn("[Autopilot::Fail] notify failed: #{e.message}")
      end
    end
  end
end
