# frozen_string_literal: true

module Operations
  module Approvals
    # Reverts a just-approved ticket back to pending within the undo window. Once
    # the deferred OnFullyApproved has advanced the ticket (no longer production),
    # undo is refused — the decision has already taken effect downstream.
    class Undo < Operations::Base
      def initialize(ticket:, actor: nil)
        @ticket = ticket
        @actor = actor
      end

      def call
        raise Operations::Errors::Invalid, I18n.t('operations.approvals.already_completed') unless @ticket.production?

        # Revert BOTH the approved winners and the not_selected losers so every slot
        # re-opens exactly as it was before the decision. (approvable_creatives hides
        # not_selected, so query the raw creatives here.)
        @ticket.creatives.select { |c| c.approval_approved? || c.approval_not_selected? }.each do |creative|
          creative.update!(approval_state: 'pending', decided_at: nil, reviewed_by: nil)
        end
        Broadcaster.ticket(@ticket, 'approval_updated', decision: 'undone')
        Operations::Notes::Create.call(ticket: @ticket, user: nil, kind: :system, i18n_key: 'notes.approval.undone')
        @ticket
      end
    end
  end
end
