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
        create_review_task

        regenerate_if_go
        @creative
      end

      private

      # A concrete to-do for the ticket owner: review the client's requested changes
      # on this piece. Assigned to the responsible user so it surfaces on My Tasks.
      def create_review_task
        Operations::Subtasks::Create.call(
          ticket: @ticket,
          assignee_id: @ticket.responsible_user&.id,
          title: "Revisar ajustes do cliente — #{slot_label}: #{@feedback.to_s.truncate(120)}"
        )
      end

      def slot_label = ::Creatives.spec_for(@creative.creative_type)&.dig(:label) || @creative.creative_type

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
