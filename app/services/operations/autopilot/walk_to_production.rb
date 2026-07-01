# frozen_string_literal: true

module Operations
  module Autopilot
    # Phase 1: walk the ticket forward to `production`, filling each stage's fields
    # on the way. Reuses the authoritative ChangeStatus for every step and runs the
    # existing CarryOver SYNCHRONOUSLY after each move (instead of the async
    # CarryOverFieldsJob) so the briefing/scope/caption fields are populated before
    # the creatives are generated — "o estrategista preenche todos os campos".
    class WalkToProduction < Operations::Base
      TARGET = 'production'

      def initialize(run:)
        @run = run
        @ticket = run.ticket
      end

      def call
        return unless claim!

        walk_forward_to(TARGET)

        @run.update!(state: 'generating')
        Broadcaster.ticket(@ticket, 'autopilot_progress', run_id: @run.id, state: 'generating')
        AutopilotAdvanceJob.perform_later(@run.id)
      end

      private

      # Claim the run out of `pending` exactly once.
      def claim!
        @run.with_lock do
          next false unless @run.state == 'pending'

          @run.update!(state: 'scoping')
          true
        end
      end

      def walk_forward_to(target)
        target_idx = Ticket::WORKFLOW.index(target.to_sym)
        while (idx = @ticket.workflow_step) && idx < target_idx
          next_status = Ticket::WORKFLOW[idx + 1].to_s
          Operations::Tickets::ChangeStatus.call(@ticket, next_status, user: @run.user, force: true)
          @ticket.reload
          fill_fields_now
          @ticket.reload
        end
      end

      # Synchronous carry-over + AI field fill for the stage just entered. The
      # async CarryOverFieldsJob ChangeStatus also enqueues will then find nothing
      # blank left to fill and no-op.
      def fill_fields_now
        Operations::Tickets::CarryOver.call(ticket: @ticket, status: @ticket.status)
      rescue StandardError => e
        Rails.logger.warn("[Autopilot::WalkToProduction] carry-over failed for #{@ticket.id}: #{e.message}")
      end
    end
  end
end
