# frozen_string_literal: true

module Operations
  module Approvals
    # The client approves a whole ticket from the portal: every pending approvable
    # creative is marked approved immediately, but the flow-advancing side effect
    # (OnFullyApproved → advance + optional auto-publish) is DEFERRED past the undo
    # window so the client can still undo. NotifyDecision runs once per action.
    class ApproveTicket < Operations::Base
      UNDO_WINDOW = 6.seconds

      def initialize(ticket:, actor:)
        @ticket = ticket
        @actor = actor
      end

      def call
        set = @ticket.approvable_creatives.select(&:approval_pending?)
        raise Operations::Errors::Invalid, 'Não há conteúdo pendente para aprovar.' if set.empty?

        set.each do |creative|
          creative.update!(approval_state: 'approved', reviewed_by: @actor, decided_at: Time.current, client_feedback: nil)
        end
        Broadcaster.ticket(@ticket, 'approval_updated', decision: 'approved')
        NotifyDecision.call(ticket: @ticket, decision: 'approved', actor: @actor)
        OnFullyApprovedJob.set(wait: UNDO_WINDOW).perform_later(@ticket.id)
        @ticket
      end
    end
  end
end
