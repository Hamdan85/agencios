# frozen_string_literal: true

module Controllers
  module Autopilot
    # POST /tickets/:id/autopilot_estimate  (target: :ticket)
    # POST /projects/:id/autopilot_estimate (target: :project)
    #
    # Returns the credit estimate + eligibility for a GO run. Never charges. For a
    # project it prices every candidate ticket and reports any blockers, so the UI
    # can show the breakdown, a shortfall + buy-credits prompt, or the tickets that
    # must be resolved first (a project GO is blocked when any is ineligible).
    class Estimate < Base
      def initialize(params:, target: :ticket)
        @params = params
        @target = target.to_sym
      end

      def call
        deny_guests!
        { estimate: Operations::Autopilot::Estimate.call(tickets: tickets, workspace: workspace) }
      end

      private

      def tickets
        if @target == :project
          project = workspace.projects.find(@params[:id])
          Operations::Autopilot::StartBatch.candidate_tickets(project).to_a
        else
          [workspace.tickets.find(@params[:id])]
        end
      end
    end
  end
end
