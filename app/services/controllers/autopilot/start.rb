# frozen_string_literal: true

module Controllers
  module Autopilot
    # POST /tickets/:id/autopilot_start  (target: :ticket)
    # POST /projects/:id/autopilot_start (target: :project)  body: { mode, scheduled_at }
    #
    # Confirms and launches a GO run. Re-validates eligibility (authoritative) and
    # the whole-run credit balance before anything is created — a shortfall raises
    # InsufficientCredits (→ 402 with required/available), a project with any
    # manual-creative ticket is blocked (→ 422). Once past the gates the run(s)
    # walk on their own.
    class Start < Base
      def initialize(params:, target: :ticket)
        @params = params
        @target = target.to_sym
      end

      def call
        deny_guests!
        require_billing!
        @target == :project ? start_project : start_ticket
      end

      private

      def start_ticket
        ticket = workspace.tickets.find(@params[:id])
        unless Operations::Autopilot::Eligibility.call(ticket: ticket)[:eligible]
          raise Operations::Errors::Invalid, I18n.t('api.autopilot.ticket_requires_manual_creatives')
        end

        ensure_credits!([ticket])
        run = Operations::Autopilot::Start.call(
          ticket: ticket, user: user, mode: mode, scheduled_at: @params[:scheduled_at]
        )
        { run: serialize(run, AutopilotRunSerializer) }
      end

      def start_project
        project = workspace.projects.find(@params[:id])
        tickets = Operations::Autopilot::StartBatch.candidate_tickets(project).to_a
        estimate = Operations::Autopilot::Estimate.call(tickets: tickets, workspace: workspace)
        unless estimate[:eligible]
          raise Operations::Errors::Invalid,
                I18n.t('api.autopilot.project_requires_manual_creatives')
        end

        ensure_credits!(tickets)
        result = Operations::Autopilot::StartBatch.call(project: project, user: user, mode: mode)
        {
          batch: serialize(result[:batch], AutopilotRunSerializer),
          runs: serialize_collection(result[:runs], AutopilotRunSerializer)
        }
      end

      # Whole-run credit pre-check (mirrors Controllers::Base#require_credits!,
      # but summed across the run). Unlimited godfathered workspaces skip it.
      def ensure_credits!(tickets)
        return if workspace&.godfathered? && !workspace.credit_limited?

        Operations::Credits::EnsureGodfatheredGrant.call(workspace: workspace) if workspace&.credit_limited?

        estimate = Operations::Autopilot::Estimate.call(tickets: tickets, workspace: workspace)
        return if estimate[:shortfall].to_i <= 0

        raise Operations::Errors::InsufficientCredits.new(
          required: estimate[:total_credits], available: estimate[:available]
        )
      end

      def mode = @params[:mode].to_s.presence_in(AutopilotRun::MODES) || 'scheduled'
    end
  end
end
