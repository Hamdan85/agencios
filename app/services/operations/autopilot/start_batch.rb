# frozen_string_literal: true

module Operations
  module Autopilot
    # Project/strategy-level GO: a coordinator run plus one child ticket-run per
    # eligible ticket. The controller has already blocked the whole GO if any
    # candidate is ineligible; this filters defensively and starts the rest as
    # independent runs (one failing ticket must not block the others).
    class StartBatch < Operations::Base
      # Tickets a project GO considers: not-yet-scheduled, active tickets, in board
      # order. Shared with the controller so the estimate and the start agree.
      def self.candidate_tickets(project)
        statuses = Ticket.statuses.values_at('ideation', 'scoping', 'production')
        project.tickets.active.where(status: statuses).board_ordered
      end

      def initialize(project:, user:, mode: 'scheduled')
        @project = project
        @user = user
        @mode = mode.to_s
      end

      def call
        tickets = eligible_tickets
        raise Operations::Errors::Invalid, I18n.t('operations.autopilot.none_eligible') if tickets.empty?

        # Clicking GO is an explicit user action — the "GO mode": it starts a draft
        # project (→ active) and executes its tickets. Planning alone never does this.
        Operations::Projects::Start.call(project: @project, user: @user) if @project.status_draft?

        batch = create_batch(tickets)
        runs = tickets.map do |ticket|
          Operations::Autopilot::Start.call(ticket: ticket, user: @user, mode: @mode, batch: batch)
        end
        Broadcaster.board(@project.workspace_id, 'autopilot_batch_started',
                          batch_id: batch.id, project_id: @project.id, total: runs.size)
        { batch: batch, runs: runs }
      end

      private

      def eligible_tickets
        self.class.candidate_tickets(@project).select do |ticket|
          Operations::Autopilot::Eligibility.call(ticket: ticket)[:eligible]
        end
      end

      def create_batch(tickets)
        estimate = Operations::Autopilot::Estimate.call(tickets: tickets, workspace: @project.workspace)
        AutopilotRun.create!(
          workspace: @project.workspace, user: @user, scope: 'batch', state: 'running',
          mode: @mode.presence_in(AutopilotRun::MODES) || 'scheduled',
          estimated_credits: estimate[:total_credits], started_at: Time.current, progress: {}
        )
      end
    end
  end
end
