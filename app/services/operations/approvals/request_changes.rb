# frozen_string_literal: true

module Operations
  module Approvals
    # A client requested changes on ONE creative from the portal. Records the
    # decision + feedback as history, notifies the responsible user, and sends the
    # ticket BACK to Produção — the column whose action is "produce", which is
    # exactly what the ticket now needs.
    #
    # Nothing is regenerated here, GO ticket or not: a regeneration spends the
    # workspace's credits, so only the TEAM may trigger it (from Produção, with the
    # client's feedback in front of them). A client clicking "pedir ajustes" must
    # never be able to burn credits — they'd bounce the piece as many times as they
    # feel like. The team redoes the work and resubmits it with "Enviar para
    # aprovação".
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
        back_to_production
        @creative
      end

      private

      # The work is with the team again — put the card where its action lives.
      # `force`: the client is not a workspace user, so the regression guard has no
      # membership to check.
      def back_to_production
        return unless @ticket.approval?

        Operations::Tickets::ChangeStatus.call(@ticket, 'production', user: nil, force: true)
        @ticket.reload
      end

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
    end
  end
end
