# frozen_string_literal: true

module Operations
  module Autopilot
    # Creates a ticket-run and kicks off the walk. Idempotent: if the ticket
    # already has an active run, that run is returned instead of a second one
    # (unique partial index also enforces this at the DB level).
    #
    # Credit sufficiency is enforced by the controller before this is called; the
    # eligibility re-check here is a last authoritative guard.
    class Start < Operations::Base
      def initialize(ticket:, user:, mode: 'scheduled', scheduled_at: nil, batch: nil)
        @ticket = ticket
        @user = user
        @mode = mode.to_s
        @scheduled_at = scheduled_at
        @batch = batch
      end

      def call
        existing = AutopilotRun.ticket_runs.active.find_by(ticket_id: @ticket.id)
        return existing if existing

        unless Operations::Autopilot::Eligibility.call(ticket: @ticket)[:eligible]
          raise Operations::Errors::Invalid, 'Ticket não é elegível para o modo GO.'
        end

        run = create_run
        Broadcaster.ticket(@ticket, 'autopilot_started',
                           run_id: run.id, estimated_credits: run.estimated_credits)
        Broadcaster.board(@ticket.workspace_id, 'autopilot_started',
                          ticket_id: @ticket.id, run_id: run.id)
        AutopilotAdvanceJob.perform_later(run.id)
        run
      end

      private

      def create_run
        AutopilotRun.create!(
          workspace: @ticket.workspace, ticket: @ticket, user: @user, batch: @batch,
          scope: 'ticket', state: 'pending', target_status: 'production',
          mode: effective_mode, scheduled_at: resolved_scheduled_at,
          estimated_credits: estimated_credits, started_at: Time.current, progress: {}
        )
      end

      def estimated_credits
        Operations::Autopilot::Estimate.call(tickets: [@ticket], workspace: @ticket.workspace)[:total_credits]
      end

      def resolved_scheduled_at
        @scheduled_at.presence || @ticket.scheduled_at
      end

      # Fall back to publishing immediately when the caller asked to schedule but
      # there is no target moment anywhere (no run/ticket scheduled_at).
      def effective_mode
        return 'immediate' if @mode == 'scheduled' && resolved_scheduled_at.blank?

        @mode.presence_in(AutopilotRun::MODES) || 'scheduled'
      end
    end
  end
end
