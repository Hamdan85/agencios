# frozen_string_literal: true

module Operations
  module Approvals
    # A client requested changes on ONE creative from the portal. Records the
    # decision + feedback as history, notifies the responsible user, and routes:
    #   - video          → stays in production (never auto-regenerated)
    #   - non-video + GO  → Autopilot::Regenerate (new generation with the feedback)
    #   - non-video manual → stays in production for the team to handle
    # The ticket itself stays in production throughout (it only advances on full
    # approval), so there is no status change here.
    class RequestChanges < Operations::Base
      def initialize(creative:, feedback:, actor:)
        @creative = creative
        @feedback = feedback.to_s
        @actor = actor
        @ticket = creative.ticket
      end

      def call
        @creative.update!(
          approval_state: 'changes_requested', reviewed_by: @actor,
          decided_at: Time.current, client_feedback: @feedback.presence
        )
        Broadcaster.ticket(@ticket, 'approval_updated', creative_id: @creative.id, decision: 'changes_requested')
        NotifyDecision.call(ticket: @ticket, decision: 'changes_requested', actor: @actor,
                            creative: @creative, feedback: @feedback)

        regenerate_if_go
        @creative
      end

      private

      def video? = ::Creatives.spec_for(@creative.creative_type)&.dig(:kind) == 'video'

      # The GO run that produced this ticket (if any). Its presence means the ticket
      # is under autopilot, so a non-video change kicks a regeneration.
      def autopilot_run = @ticket.autopilot_runs.order(created_at: :desc).first

      def regenerate_if_go
        return if video? # video always waits in production

        run = autopilot_run
        return unless run # manual ticket — team handles it in production

        Operations::Autopilot::Regenerate.call(run: run, creative: @creative, feedback: @feedback)
      end
    end
  end
end
