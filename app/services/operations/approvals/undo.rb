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
        raise Operations::Errors::Invalid, 'A aprovação já foi concluída.' unless @ticket.production?

        @ticket.approvable_creatives.select(&:approval_approved?).each do |creative|
          creative.update!(approval_state: 'pending', decided_at: nil, reviewed_by: nil)
        end
        Broadcaster.ticket(@ticket, 'approval_updated', decision: 'undone')
        Operations::Notes::Create.call(ticket: @ticket, user: nil, kind: :system, body: 'Aprovação desfeita pelo cliente.')
        @ticket
      end
    end
  end
end
